# distutils: language=c++
#
# cython: language_level=3
# cython: profile=False
# cython: embedsignature=True
# cython: infer_types=True

cimport simtrie.simtrie
from simtrie.simtrie cimport *

import collections
import sys
import pickle
import io
import os
import msgpack

from libc.stdint cimport uint8_t, uint16_t, uint64_t
from libcpp.string cimport string
from libcpp.vector cimport vector

cimport posix.fcntl
cimport posix.unistd
from posix.mman cimport mmap, munmap, PROT_READ, MAP_SHARED

cdef void *MAP_FAILED = <void*>(-1)

cdef extern from *:
	"""
	#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
	"""
cimport numpy as np
np.import_array()

cdef bint write_to_stream(void *stream, void *buf, size_t size):
	# see https://gist.github.com/GaelVaroquaux/1249305
	cdef np.npy_intp shape[1]
	shape[0] = <np.npy_intp> size
	ndarray = np.PyArray_SimpleNewFromData(1, shape, np.NPY_INT8, buf)

	cdef object s = <object>stream
	n = s.write(ndarray)
	return False if n is None else n == size

cdef bint read_from_stream(void *stream, void *buf, size_t size):
	# see https://gist.github.com/GaelVaroquaux/1249305
	cdef np.npy_intp shape[1]
	shape[0] = <np.npy_intp> size
	ndarray = np.PyArray_SimpleNewFromData(1, shape, np.NPY_INT8, buf)

	cdef object s = <object>stream
	n = s.readinto(ndarray)
	return False if n is None else n == size

cdef class Iterator:
	cdef Completer completer
	cdef bytes b_prefix

	def __init__(self, Set owner, unicode prefix):
		cdef Dictionary *dct = &owner.dct
		cdef BaseType index = dct.root()

		self.completer.set_dic(owner.dct)
		self.completer.set_guide(owner.guide)

		if prefix:
			b_prefix = prefix.encode("utf8")

			if not dct.Follow(<CharType*>b_prefix, &index):
				raise StopIteration

			self.completer.Start(index, b_prefix, len(b_prefix))
		else:
			self.completer.Start(index, b"", 0)

	def __iter__(self):
		return self

cdef class KeyIterator(Iterator):
	def __next__(self):
		if self.completer.Next():
			return (<char*>self.completer.key()).decode("utf8")
		else:
			raise StopIteration

cdef class ValueIterator(Iterator):
	cdef object _values

	def __init__(self, Set owner, unicode prefix, values):
		super().__init__(owner, prefix)
		self._values = values

	def __next__(self):
		if self.completer.Next():
			return self._values[self.completer.value()]
		else:
			raise StopIteration

cdef class KeyValueIterator(Iterator):
	cdef object _values

	def __init__(self, Set owner, unicode prefix, values):
		super().__init__(owner, prefix)
		self._values = values

	def __next__(self):
		if self.completer.Next():
			return ((<char*>self.completer.key()).decode("utf8"), self._values[self.completer.value()])
		else:
			raise StopIteration

def sorted(iterable):
	elements = [(<unicode>key).encode('utf8')
		if isinstance(key, unicode) else key for key in iterable]
	elements.sort()
	return elements

def _to_numpy_array(values):
	# returns None if no compact numpy array could be created.
	pass


cdef class Any_:
	pass

Any = Any_()

cdef class Metric:
	cdef Costs[float] costs

	def __init__(self, *rules):
		cdef bint ok
		cdef bint p_old, p_new

		def to_ord(x):
			if isinstance(x, str):
				return ord(x)
			else:
				return x

		for (old, new), cost in rules:
			if old is None:  # insert?
				if new is Any:
					ok = self.costs.set_insert_cost(cost)
				else:
					ok = self.costs.set_insert_cost(to_ord(new), cost)
			elif new is None:  # delete?
				if old is Any:
					ok = self.costs.set_delete_cost(cost)
				else:
					ok = self.costs.set_delete_cost(to_ord(old), cost)
			else:
				p_old = isinstance(old, (tuple, str)) and len(old) == 2
				p_new = isinstance(new, (tuple, str)) and len(new) == 2

				if p_old and p_new:  # transpose?
					if tuple(reversed(old)) == tuple(new):
						ok = self.costs.set_transpose_cost(
							to_ord(old[0]), to_ord(old[1]), cost)
					else:
						ok = False
				elif p_old and not p_new:  # merge
					ok = self.costs.set_merge_cost(
						to_ord(old[0]), to_ord(old[1]), to_ord(new), cost)
				elif not p_old and p_new:  # split
					ok = self.costs.set_split_cost(
						to_ord(old), to_ord(new[0]), to_ord(new[1]), cost)
				else:  # replace
					ok = self.costs.set_replace_cost(to_ord(old), to_ord(new), cost)

			if not ok:
				raise ValueError("illegal cost rule (%s, %s) -> %s" % (old, new, cost))


cdef class Set:
	cdef int _size
	cdef Dictionary dct
	cdef Dawg dawg
	cdef Guide guide
	cdef bint _completions
	cdef Completer completer

	cdef int _fd
	cdef void *_mmap_addr
	cdef size_t _mmap_size

	def __init__(self, iterable=None, sorted=False, completions=True):
		self._completions = completions
		self._build_from_iterable(iterable, sorted)
		self._fd = -1

	def __dealloc__(self):
		self.dct.Clear()
		self.dawg.Clear()
		self.guide.Clear()

	def _build_dawg(self, iterable, sorted):
		if iterable is None:
			elements = []
		elif not sorted:
			elements = [(<unicode>key).encode('utf8')
				if isinstance(key, unicode) else key for key in iterable]
			elements.sort()
		else:
			elements = iterable

		cdef DawgBuilder dawg_builder
		cdef bytes b_key
		cdef bytes b_last_key = None
		cdef bint check_order = False
		cdef int n = 0

		for key in elements:
			if isinstance(key, unicode):
				b_key = <bytes>(<unicode>key).encode('utf8')
			else:
				b_key = key

			if check_order and b_key < b_last_key:
				raise ValueError("input is not sorted at key %s" % key)
			if b_key == b_last_key:
				continue  # ignore duplicate keys

			if not dawg_builder.Insert(b_key, len(b_key), 0):
				raise ValueError("error on inserting key %s" % key)

			n += 1
			b_last_key = b_key
			check_order = sorted

		if not dawg_builder.Finish(&self.dawg):
			raise RuntimeError("internal error in dawg building")

		self._size = n

	def _build_from_iterable(self, iterable, sorted):
		self._build_dawg(iterable, sorted)

		if not DictionaryBuilder.Build(self.dawg, &self.dct):
			raise RuntimeError("dictionary building failed")

		if self._completions:
			if not GuideBuilder.Build(self.dawg, self.dct, &self.guide):
				raise RuntimeError("completion guide building failed")

			self.completer.set_dic(self.dct)
			self.completer.set_guide(self.guide)

	cpdef bytes tobytes(self):
		cdef bytes res
		stream = io.BytesIO()
		try:
			self.dump(stream)
			res = stream.getvalue()
		finally:
			stream.close()
		return res

	cpdef frombytes(self, bytes data):
		stream = io.BytesIO(data)
		try:
			self.read(stream)
		finally:
			stream.close()
		return self

	def dump(self, f):
		f.write(self._size.to_bytes(8, byteorder='big'))
		res = self.dct.Write(&write_to_stream, <void*>f)
		if res and self._completions:
			self.guide.Write(&write_to_stream, <void*>f)
		if not res:
			raise IOError("write failed")
		return self

	def read(self, f):
		self._size = int.from_bytes(f.read(8), 'big')
		res = self.dct.Read(&read_from_stream, <void*>f)
		if res and self._completions:
			res = self.guide.Read(&read_from_stream, <void*>f)
		if not res:
			self.dct.Clear()
			self.guide.Clear()
			raise IOError("read failed")
		return self

	@staticmethod
	def load(f):
		if isinstance(f, bytes):
			return Set().frombytes(f)
		else:
			return Set().read(f)

	def _open(self, unicode path):
		if self._fd >= 0:
			self.close()

		cdef size_t size = os.path.getsize(path)

		cdef int fd = posix.fcntl.open(
			path.encode("utf8"), posix.fcntl.O_RDONLY)
		if fd < 0:
			raise IOError("failed to open " + path)

		cdef void *buf = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0)
		if buf == MAP_FAILED:
			posix.unistd.close(self._fd)
			raise IOError("failed to mmap file " + path)

		self._fd = fd
		self._mmap_addr = buf
		self._mmap_size = size

		cdef bytes b_size = (<const uint8_t*>(buf))[0:8]
		self._size = int.from_bytes(b_size, 'big')

		cdef const void *buf1 = self.dct.Map(<const uint8_t*>(buf) + 8)
		if self._completions:
			self.guide.Map(buf1)

		return self

	def close(self):
		self.dct.Clear()
		self.guide.Clear()

		if self._fd >= 0:
			munmap(self._mmap_addr, self._mmap_size)
			posix.unistd.close(self._fd)
			self._fd = -1

		return self

	def file_size(self):
		return 8 + self.dct.file_size() + self.guide.file_size()

	def prefixes(self, key):
		cdef BaseType index = self.dct.root()
		cdef bytes b_key
		cdef bint use_bytes
		cdef int pos = 1
		cdef CharType ch

		if isinstance(key, bytes):
			b_key = key
			use_bytes = True
		else:
			b_key = <bytes>key.encode('utf8')
			use_bytes = False

		for ch in b_key:
			if not self.dct.Follow(ch, &index):
				return
			if self.dct.has_value(index):
				if use_bytes:
					yield b_key[:pos]
				else:
					yield b_key[:pos].decode('utf8')
			pos += 1

	def keys(self, unicode prefix=""):
		if not self._completions:
			raise RuntimeError("iterations are not enabled")
		try:
			return KeyIterator(self, prefix)
		except StopIteration:
			return []

	cdef _init_nearest(self, Similar[float] *nearest, unicode search, int max_cost, Metric metric, dict kwargs):
		nearest.set_dic(self.dct)
		nearest.set_guide(self.guide)

		if metric:
			nearest.set_costs(metric.costs)

		nearest.set_enable_transpose(kwargs.get("allow_transpose", False))
		nearest.set_enable_merge(kwargs.get("allow_merge", False))
		nearest.set_enable_split(kwargs.get("allow_split", False))

		cdef bytes b_search = search.encode('utf8')
		nearest.start(b_search, len(b_search), max_cost)

	def similar(self, search, max_cost=1, metric=None, **kwargs):
		cdef Similar[float] nearest
		self._init_nearest(&nearest, search, max_cost, metric, kwargs)
		cdef str key

		while nearest.next():
			key = nearest.key()[:nearest.key_length()].decode("utf8")
			yield key, nearest.cost()

	def lcs(self, search, min_length=3):
		cdef LCS lcs
		cdef str key

		lcs.set_dic(self.dct)
		lcs.set_guide(self.guide)

		cdef bytes b_search = search.encode('utf8')
		lcs.start(b_search, len(b_search), min_length)

		while lcs.next():
			seq = lcs.lcs()[:lcs.lcs_length()].decode("utf8")
			key = lcs.key()[:lcs.key_length()].decode("utf8")
			yield seq, key


	def __contains__(self, key):
		cdef bytes b_key
		if isinstance(key, bytes):
			b_key = key
		else:
			b_key = <bytes>key.encode('utf8')
		return self.dct.Contains(b_key, len(b_key))

	def __len__(self):
		return self._size

	def __iter__(self):
		try:
			return KeyIterator(self, "")
		except StopIteration:
			return []

	def __enter__(self):
		return self

	def __exit__(self, *args):
		self.close()

	# pickling support
	def __reduce__(self):
		return self.__class__, tuple(), self.tobytes()

	def __setstate__(self, state):
		self.frombytes(state)

cdef class Dict(Set):
	cdef object _values

	def __init__(self, *args, completions=False, **kwargs):
		if len(args) == 1 and isinstance(args[0], dict):
			args = [args[0].items()]
		super().__init__(*args, **kwargs)

	def  __getitem__(self, key):
		cdef bytes b_key = <bytes>key.encode('utf8')
		index = self.dct.Find(b_key, len(b_key))
		if index < 0:
			raise KeyError(key)
		return self._values[index]

	def keys(self, unicode prefix=""):
		try:
			return KeyIterator(self, prefix)
		except StopIteration:
			return []

	def values(self, unicode prefix=""):
		if not prefix:
			return self._values
		else:
			try:
				return ValueIterator(self, prefix, self._values)
			except StopIteration:
				return []

	def items(self, unicode prefix=""):
		try:
			return KeyValueIterator(self, prefix, self._values)
		except StopIteration:
			return []

	def similar(self, search, max_cost=1, metric=None, **kwargs):
		cdef Similar[float] nearest
		self._init_nearest(&nearest, search, max_cost, metric, kwargs)
		cdef str key

		while nearest.next():
			key = nearest.key()[:nearest.key_length()].decode("utf8")
			yield key, self._values[nearest.value()], nearest.cost()

	def dump(self, f):
		super().dump(f)
		if isinstance(self._values, np.ndarray):
			self._values.dump(f)
		else:
			f.write(msgpack.packb(self._values, use_bin_type=True))
		return self

	def read(self, f):
		super().read(f)
		data = f.read()
		#np.load(f)
		self._values = msgpack.unpackb(data, use_list=False, raw=False)
		return self

	@staticmethod
	def load(f):
		if isinstance(f, bytes):
			return Dict().frombytes(f)
		else:
			return Dict().read(f)

	def _open(self, unicode path):
		raise NotImplementedError("mmap support for Dict not yet implemented")
		super()._open(path)
		self._values = []
		# msgpack.unpackb(_mem_addr + , use_list=False, raw=False)
		# FIXME

	def file_size(self):
		return super().file_size() + len(msgpack.packb(self._values, use_bin_type=True))

	def _build_dawg(self, iterable, sorted):
		if iterable is None:
			elements = []
		elif not sorted:
			elements = [((<unicode>key).encode('utf8'), value)
				if isinstance(key, unicode) else (key, value) for key, value in iterable]
			elements.sort(key=lambda kv: kv[0])
		else:
			elements = iterable

		cdef DawgBuilder dawg_builder
		cdef bytes b_key
		cdef bytes b_last_key = None
		cdef bint check_order = False
		cdef int index
		cdef object values = []

		for index, key in enumerate(elements):
			key, value = key
			values.append(value)

			if isinstance(key, unicode):
				b_key = <bytes>(<unicode>key).encode('utf8')
			else:
				b_key = key

			if check_order and b_key < b_last_key:
				raise ValueError("input is not sorted at key %s" % key)
			if b_key == b_last_key:
				raise ValueError("input contained duplicate key %s" % key)

			if not dawg_builder.Insert(b_key, len(b_key), index):
				raise RuntimeError("error on inserting key %s" % key)

			b_last_key = b_key
			check_order = sorted

		'''
		cdef tuple int_types = (np.int8, np.int16, np.int32, np.int64)
		cdef int best_int_type = 0

		if best_int_type >= 0 and isinstance(value, int):
			while best_int_type < len(int_types):
				info = np.iinfo[int_types[best_int_type]]
				if value >= info.min and value <= info.max:
					break
				best_int_type += 1
		else:
			best_int_type = -1
		'''

		self._values = tuple(values)

		# numpy.asarray(values)

		if not dawg_builder.Finish(&self.dawg):
			raise RuntimeError("internal error in dawg building")

def open(unicode path):
	return Set()._open(path)



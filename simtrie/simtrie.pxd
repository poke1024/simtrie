cdef extern from "../lib/dawgdic/base-types.h" namespace "dawgdic":
	# 8-bit characters.
	ctypedef char CharType
	ctypedef unsigned char UCharType

	# 32-bit integer.
	ctypedef int ValueType

	# 32-bit unsigned integer.
	ctypedef unsigned int BaseType

	# 32 or 64-bit unsigned integer.
	ctypedef int SizeType

	# Function for reading and writing data.
	ctypedef bint (*IOFunction)(void *stream, void *buf, size_t size)

cdef extern from "../lib/dawgdic/completer.h" namespace "dawgdic" nogil:
	cdef cppclass Completer:
		Completer()
		Completer(Dictionary &dic, Guide &guide)

		void set_dic(Dictionary &dic)
		void set_guide(Guide &guide)

		Dictionary &dic()
		Guide &guide()

		# These member functions are available only when Next() returns true.
		char *key()
		SizeType length()
		ValueType value()

		# Starts completing keys from given index and prefix.
		void Start(BaseType index)
		void Start(BaseType index, char *prefix)
		void Start(BaseType index, char *prefix, SizeType length)

		# Gets the next key.
		bint Next()

cdef extern from "../lib/dawgdic/dawg.h" namespace "dawgdic":

	cdef cppclass Dawg:
		Dawg()

		# The root index.
		BaseType root() nogil

		# Number of units.
		SizeType size() nogil

		# Number of transitions.
		SizeType num_of_transitions() nogil

		# Number of states.
		SizeType num_of_states() nogil

		# Number of merged transitions.
		SizeType num_of_merged_transitions() nogil

		# Number of merged states.
		SizeType num_of_merged_states() nogil

		# Number of merging states.
		SizeType num_of_merging_states() nogil

		# Reads values.
		BaseType child(BaseType index) nogil

		BaseType sibling(BaseType index) nogil

		ValueType value(BaseType index) nogil

		bint is_leaf(BaseType index) nogil

		UCharType label(BaseType index) nogil

		bint is_merging(BaseType index) nogil

		# Clears object pools.
		void Clear() nogil

		# Swaps dawgs.
		void Swap(Dawg *dawg) nogil

cdef extern from "../lib/dawgdic/dawg-builder.h" namespace "dawgdic":
	cdef cppclass DawgBuilder:

		DawgBuilder() nogil  #(SizeType initial_hash_table_size = DEFAULT_INITIAL_HASH_TABLE_SIZE)

		# Number of units.
		SizeType size() nogil

		# Number of transitions.
		SizeType num_of_transitions() nogil

		# Number of states.
		SizeType num_of_states() nogil

		# Number of merged transitions.
		SizeType num_of_merged_transitions() nogil

		# Number of merged states.
		SizeType num_of_merged_states() nogil

		# Number of merging states.
		SizeType num_of_merging_states() nogil

		# Initializes a builder.
		void Clear() nogil

		# Inserts a key.
		bint Insert(CharType *key)
		bint Insert(CharType *key, ValueType value)
		bint Insert(CharType *key, SizeType length, ValueType value)

		# Finishes building a dawg.
		bint Finish(Dawg *dawg)

cdef extern from "../lib/dawgdic/dictionary.h" namespace "dawgdic":
	cdef cppclass Dictionary:

		Dictionary() nogil

		DictionaryUnit *units() nogil
		SizeType size() nogil
		SizeType total_size() nogil
		SizeType file_size() nogil

		# Root index.
		BaseType root() nogil

		# Checks if a given index is related to the end of a key.
		bint has_value(BaseType index) nogil

		# Gets a value from a given index.
		ValueType value(BaseType index) nogil

		# Reads a dictionary from an input stream.
		bint Read(IOFunction read, void *stream) except +

		# Writes a dictionry to an output stream.
		bint Write(IOFunction write, void *stream) except +

		# Exact matching.
		bint Contains(CharType *key) nogil
		bint Contains(CharType *key, SizeType length) nogil

		# Exact matching.
		ValueType Find(CharType *key) nogil
		ValueType Find(CharType *key, SizeType length) nogil
		bint Find(CharType *key, ValueType *value) nogil
		bint Find(CharType *key, SizeType length, ValueType *value) nogil

		# Follows a transition.
		bint Follow(CharType label, BaseType *index) nogil

		# Follows transitions.
		bint Follow(CharType *s, BaseType *index) nogil
		bint Follow(CharType *s, BaseType *index, SizeType *count) nogil

		# Follows transitions.
		bint Follow(CharType *s, SizeType length, BaseType *index) nogil
		bint Follow(CharType *s, SizeType length, BaseType *index, SizeType *count) nogil

		# Maps memory with its size.
		const void *Map(const void *address) nogil

		# Initializes a dictionary.
		void Clear() nogil

		# Swaps dictionaries.
		void Swap(Dictionary *dic) nogil
		# Shrinks a vector.
		void Shrink() nogil

cdef extern from "../lib/dawgdic/dictionary-builder.h" namespace "dawgdic::DictionaryBuilder":
	cdef cppclass DictionaryBuilder:
		@staticmethod
		bint Build (Dawg &dawg, Dictionary *dic) nogil

cdef extern from "../lib/dawgdic/dictionary-unit.h" namespace "dawgdic":
	cdef cppclass DictionaryUnit:

		DictionaryUnit() nogil

		# Sets a flag to show that a unit has a leaf as a child.
		void set_has_leaf() nogil

		# Sets a value to a leaf unit.
		void set_value(ValueType value) nogil

		# Sets a label to a non-leaf unit.
		void set_label(UCharType label) nogil

		# Sets an offset to a non-leaf unit.
		bint set_offset(BaseType offset) nogil


		# Checks if a unit has a leaf as a child or not.
		bint has_leaf() nogil

		# Checks if a unit corresponds to a leaf or not.
		ValueType value() nogil

		# Reads a label with a leaf flag from a non-leaf unit.
		BaseType label() nogil

		# Reads an offset to child units from a non-leaf unit.
		BaseType offset() nogil

cdef extern from "../lib/dawgdic/guide.h" namespace "dawgdic":
	cdef cppclass Guide:

		Guide()

		GuideUnit *units()
		SizeType size()
		SizeType total_size()
		SizeType file_size()

		# The root index.
		BaseType root()

		UCharType child(BaseType index)
		UCharType sibling(BaseType index)

		# Reads a dictionary from an input stream.
		bint Read(IOFunction read, void *stream)

		# Writes a dictionry to an output stream.
		bint Write(IOFunction write, void *stream) const

		# Maps memory with its size.
		const void *Map(const void *address) nogil

		# Swaps Guides.
		void Swap(Guide *Guide)

		# Initializes a Guide.
		void Clear()

cdef extern from "../lib/dawgdic/guide-builder.h" namespace "dawgdic::GuideBuilder":
	cdef cppclass GuideBuilder:
		@staticmethod
		bint Build (Dawg &dawg, Dictionary &dic, Guide* guide) nogil

cdef extern from "../lib/dawgdic/guide-unit.h" namespace "dawgdic":
	cdef cppclass GuideUnit:
		GuideUnit() nogil

		void set_child(UCharType child) nogil
		void set_sibling(UCharType sibling) nogil
		UCharType child() nogil
		UCharType sibling() nogil
from libcpp.string cimport string
from libcpp cimport bool

cdef extern from "../lib/dawgdic/similar.h" namespace "dawgdic" nogil:
	cdef cppclass Costs[CostType]:
		bint set_insert_cost(CostType cost)
		bint set_insert_cost(const UCharType k, CostType cost)
		bint set_delete_cost(CostType cost)
		bint set_delete_cost(const UCharType k, CostType cost)
		bint set_replace_cost(const UCharType k1, const UCharType k2, CostType cost)
		bint set_transpose_cost(const UCharType k1, const UCharType k2, CostType cost)
		bint set_split_cost(const UCharType a, const UCharType b1, const UCharType b2, CostType cost)
		bint set_merge_cost(const UCharType a1, const UCharType a2, const UCharType b, CostType cost)

	cdef cppclass LCS:
		LCS()

		void set_dic(Dictionary &dic)
		void set_guide(Guide &guide)

		# These member functions are available only when Next() returns true.
		char *key()
		SizeType key_length()
		ValueType value()
		char *lcs()
		SizeType lcs_length()

		# Starts completing keys from given index and prefix.
		void start(char *s, size_t len, int min_length) nogil

		# Gets the next key.
		bint next() nogil

	cdef cppclass Similar[CostType]:
		Similar()

		void set_dic(Dictionary &dic)
		void set_guide(Guide &guide)
		void set_costs(const Costs[CostType] &costs)

		Dictionary &dic()
		Guide &guide()

		# These member functions are available only when Next() returns true.
		char *key()
		SizeType key_length()
		ValueType value()
		CostType cost()

		# Starts completing keys from given index and prefix.
		void start(char *s, size_t len, CostType max_cost) nogil

		# Gets the next key.
		bint next() nogil

		void set_enable_transpose(bint enable)
		void set_enable_split(bint enable)
		void set_enable_merge(bint enable)

cdef extern from "<istream>" namespace "std" nogil:
	cdef cppclass istream:
		istream() except +
		istream& read (char* s, int n) except +

	cdef cppclass ostream:
		ostream() except +
		ostream& write (char* s, int n) except +

cdef extern from "<fstream>" namespace "std" nogil:
	cdef cppclass ifstream:
		ifstream() except +
		istream(char* filename) except +
		istream(char* filename, int mode) except +

		bool fail() except +

		void open(char* filename) except +
		void open(char* filename, int mode) except +
		void close() except +

		ifstream& read (char* s, int n) except +


cdef extern from "<sstream>" namespace "std":

	cdef cppclass stringstream:
		stringstream()
		stringstream(string s)
		stringstream(string s, int options)
		string str ()
		stringstream& write (char* s, int n)
		stringstream& seekg (int pos)


cdef extern from "<sstream>" namespace "std::stringstream":

#    int in
	int out
	int binary

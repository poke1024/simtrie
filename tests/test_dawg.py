# -*- coding: utf-8 -*-
from __future__ import absolute_import, unicode_literals
import pickle
from io import BytesIO

import pytest
import simtrie

def test_contains():
    d = simtrie.Dict({'foo': 1, 'bar': 2, 'foobar': 3})

    assert 'foo' in d
    assert 'bar' in d
    assert 'foobar' in d
    assert 'fo' not in d
    assert 'x' not in d

    assert b'foo' in d
    assert b'x' not in d


class TestDAWG(object):

    def test_sorted_iterable(self):

        sorted_data = ['bar', 'foo', 'foobar']
        d = simtrie.Set(sorted_data, sorted=True)

        assert 'bar' in d
        assert 'foo' in d

    def test_no_segfaults_on_invalid_file(self):
        d = simtrie.Set()

        with pytest.raises(IOError) as e:
            d.frombytes(b"foo")

    def test_no_segfaults_after_wrong_stream(self):
        d = simtrie.Set()
        assert 'random-key' not in d

    def test_build_errors(self):
        with pytest.raises(ValueError):
            data = [b'foo\x00bar', b'bar']
            simtrie.Set(data)

    def test_contains_with_null_bytes(self):
        d = simtrie.Set(['foo'])
        assert b'foo' in d
        assert b'foo\x00bar' not in d

    def test_unicode_sorting(self):
        key1 = '\uff72\uff9c\uff90\uff7b\uff9e\uff9c'
        key2 = '\U00010345\U0001033f\U00010337\U00010330\U0001033d'

        # This apparently depends on Python version:
        # assert key1 < key2
        assert key1.encode('utf8') < key2.encode('utf8')

        # Constructor should sort data according to utf8 values,
        # not according to unicode sorting rules. It will raise an exception
        # if data is sorted according to unicode rules.
        simtrie.Set([key1, key2], sorted=True)


class TestIntDAWG(object):

    def dawg(self):
        payload = {'foo': 1, 'bar': 5, 'foobar': 3}
        d = simtrie.Dict(payload)
        return payload, d

    def test_getitem(self):
        payload, d = self.dawg()
        for key in payload:
            assert d[key] == payload[key]

        with pytest.raises(KeyError):
            d['fo']

    def test_dumps_loads(self):
        payload, d = self.dawg()
        data = d.tobytes()

        d2 = simtrie.Dict.load(data)

        for key, value in payload.items():
            assert key in d2
            assert d2[key] == value

        assert list(d2.keys('foo')) == ['foo', 'foobar']
        assert list(d2.keys('b')) == ['bar']
        assert list(d2.keys('z')) == []

    def test_dump_load(self):
        payload, d = self.dawg()

        buf = BytesIO()
        d.dump(buf)
        buf.seek(0)

        d2 = simtrie.Dict.load(buf)

        for key, value in payload.items():
            assert key in d2
            assert d2[key] == value

        assert list(d2.keys('foo')) == ['foo', 'foobar']
        assert list(d2.keys('b')) == ['bar']
        assert list(d2.keys('z')) == []

    def test_pickling(self):
        payload, d = self.dawg()

        data = pickle.dumps(d)
        d2 = pickle.loads(data)

        for key, value in payload.items():
            assert key in d2
            assert d[key] == value

    def test_int_value_ranges(self):
        for val in [0, 5, 2**16-1, 2**31-1, 2**64-1, 2**128-1]:
            d = simtrie.Dict({'f': val})
            assert d['f'] == val

    def test_items(self):
        payload, d = self.dawg()
        items = list(d.items())
        for key, value in items:
            assert payload[key] == value

    def test_items_prefix(self):
        payload, d = self.dawg()
        assert list(d.items('fo')) == [('foo', 1), ('foobar', 3)]


class TestCompletionDAWG(object):
    keys = ['f', 'bar', 'foo', 'foobar']

    def dawg(self):
        return simtrie.Set(self.keys)

    def empty_dawg(self):
        return simtrie.Set()

    def test_contains(self):
        d = self.dawg()
        for key in self.keys:
            assert key in d

    def test_keys(self):
        d = self.dawg()
        assert list(d.keys()) == sorted(self.keys)

    def test_prefixes(self):
        d = self.dawg()
        assert list(d.prefixes("foobarz")) == ["f", "foo", "foobar"]
        assert list(d.prefixes("x")) == []
        assert list(d.prefixes("bar")) == ["bar"]

    def test_b_prefixes(self):
        d = self.dawg()
        assert list(d.prefixes(b"foobarz")) == [b"f", b"foo", b"foobar"]
        assert list(d.prefixes(b"x")) == []
        assert list(d.prefixes(b"bar")) == [b"bar"]

    def test_completion(self):
        d = self.dawg()

        assert list(d.keys('z')) == []
        assert list(d.keys('b')) == ['bar']
        assert list(d.keys('foo')) == ['foo', 'foobar']

    def test_has_keys_with_prefix(self):
        def has_keys_with_prefix(d, p):
            return len(list(d.keys(p))) > 0

        assert has_keys_with_prefix(self.empty_dawg(), '') == False

        d = self.dawg()
        assert has_keys_with_prefix(d, '') == True
        assert has_keys_with_prefix(d, 'b') == True
        assert has_keys_with_prefix(d, 'fo') == True
        assert has_keys_with_prefix(d, 'bo') == False

    def test_no_segfaults_on_empty_dawg(self):
        d = simtrie.Set([])
        assert list(d.keys()) == []

# adapted from:
# https://github.com/infoscout/weighted-levenshtein/blob/master/test/test.py


def test_levenshtein():

    def get_cost(a, b):
        s = simtrie.Set([a])
        for k, cost in s.similar(b, 10):
            assert k == a
            return cost

    assert get_cost("1234", "1234") == 0
    assert get_cost("1", "1234") == 3
    assert get_cost("12345", "1234") == 1

    assert get_cost("1234", "") == 4

    assert get_cost("1", "1") == 0
    assert get_cost("123", "1") == 2

    assert get_cost("1234", "12") == 2
    assert get_cost("1234", "14") == 2
    assert get_cost("1111", "1") == 3


MAX_COST = 100

def _lev(a, b, metric):
    s = simtrie.Set([a])
    for k, cost in s.similar(b, MAX_COST, metric):
        assert k == a
        return cost


def _dam_lev(a, b, metric=None):
    s = simtrie.Set([a])
    for k, cost in s.similar(b, MAX_COST, metric=metric, allow_transpose=True):
        assert k == a
        return cost


def test_dl():
    #assert(dam_lev('', '') == 0)
    #assert(dam_lev('', 'a') == 1)
    assert(_dam_lev('a', '') == 1)
    assert(_dam_lev('a', 'b') == 1)
    assert(_dam_lev('a', 'ab') == 1)
    assert(_dam_lev('ab', 'ba') == 1)
    assert(_dam_lev('ab', 'bca') == 2)
    assert(_dam_lev('bca', 'ab') == 2)
    assert(_dam_lev('ab', 'bdca') == 3)
    assert(_dam_lev('bdca', 'ab') == 3)


def test_dl_transpose1():
    metric = simtrie.Metric(
        ((None, 'c'), 1.9)  # insertion rule
    )

    def dl(a, b):
        return _dam_lev(a, b, metric)

    assert(dl('ab', 'bca') == pytest.approx(2.9))
    assert(dl('ab', 'bdca') == pytest.approx(3.9))
    assert(dl('bca', 'ab') == pytest.approx(2))


def test_dl_transpose2():
    metric = simtrie.Metric(
        (('c', None), 1.9)  # deletion rule
    )

    def dl(a, b):
        return _dam_lev(a, b, metric)

    assert(dl('bca', 'ab') == pytest.approx(2.9))
    assert(dl('bdca', 'ab') == pytest.approx(3.9))
    assert(dl('ab', 'bca') == pytest.approx(2))


def test_dl_transpose3():
    metric = simtrie.Metric(
        (('ab', 'ba'), 1.5)  # transpose rule
    )

    def dl(a, b):
        return _dam_lev(a, b, metric)

    assert(dl('ab', 'bca') == pytest.approx(2.5))
    assert(dl('bca', 'ab') == pytest.approx(2))


def test_dl_transpose4():
    metric = simtrie.Metric(
        (('ba', 'ab'), 1.5)  # transpose rule
    )

    def dl(a, b):
        return _dam_lev(a, b, metric)

    assert(dl('ab', 'bca') == pytest.approx(2))
    assert(dl('bca', 'ab') == pytest.approx(2.5))


def test_lev_insert():
    metric = simtrie.Metric(
        ((None, 'a'), 5)  # insertion rule
    )

    def lev(a, b):
        return _lev(a, b, metric)

    # assert(lev('', 'a') == 5.0)
    assert(lev('a', '') == 1.0)
    # assert(lev('', 'aa') == 10.0)
    assert(lev('a', 'aa') == 5.0)
    assert(lev('aa', 'a') == 1.0)
    assert(lev('asdf', 'asdf') == 0.0)
    assert(lev('xyz', 'abc') == 3.0)
    assert(lev('xyz', 'axyz') == 5.0)
    assert(lev('x', 'ax') == 5.0)


def test_lev_delete():
    metric = simtrie.Metric(
        (('z', None), 7.5)  # deletion rule
    )

    def lev(a, b):
        return _lev(a, b, metric)

    assert(lev('x', 'xz') == 1.0)
    assert(lev('z', '') == 7.5)
    assert(lev('xyz', 'zzxz') == 3.0)
    assert(lev('zzxzzz', 'xyz') == 18.0)


def test_lev_substitute():
    metric = simtrie.Metric(
        (('a', 'z'), 1.2),  # substitution rule
        (('z', 'a'), 0.1),  # substitution rule
    )

    def lev(a, b):
        return _lev(a, b, metric)

    assert(lev('a', 'z') == pytest.approx(1.2))
    assert(lev('z', 'a') == pytest.approx(0.1))
    assert(lev('a', '') == pytest.approx(1))
    # assert(lev('', 'a'), 1)
    assert(lev('asdf', 'zzzz') == pytest.approx(4.2))
    assert(lev('asdf', 'zz') == pytest.approx(4.0))
    assert(lev('asdf', 'zsdf') == pytest.approx(1.2))
    assert(lev('zsdf', 'asdf') == pytest.approx(0.1))


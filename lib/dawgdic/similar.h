// Written by Bernhard Liebl, April 2019.

// Based on ideas from Steven Hanov's blog article
// http://stevehanov.ca/blog/?id=114

#include <stack>
#include <unordered_map>
#include <memory>


namespace dawgdic {

bool all_null() {
	return true;
}

template <typename... T>
bool all_null(const UCharType *p_k, T... keys) {
	return !p_k && all_null(keys...);
}


// see https://gist.github.com/ueokande/e7c7cf45c26b1e79cf27
template <typename Tuple, size_t x, size_t ...xs>
constexpr auto sub_tail_tuple(const Tuple &t, std::index_sequence<x, xs...>) {
  return std::make_tuple(std::get<xs>(t)...);
}

template <typename Tuple>
constexpr auto tuple_tail(const Tuple &t) {
  constexpr size_t tuple_size = std::tuple_size<Tuple>::value;
  return sub_tail_tuple(t, std::make_index_sequence<tuple_size>());
}




template<int N, typename UCharType, typename CostType>
class CostsMap {
private:
	std::unordered_map<UCharType, CostsMap<N - 1, UCharType, CostType>> costs_;
	CostType default_;

public:
	CostsMap() : default_(1) {
	}

	template <typename... T>
	inline bool set(CostType cost, const UCharType *p_k, T... keys) {
		if (!p_k) {
			if (!all_null(keys...)) {
				return false;
			}
			costs_.clear();
			default_ = cost;
		} else {
			costs_[*p_k].set(cost, keys...);
		}
		return true;
	}

	template <typename... T>
	inline CostType operator()(UCharType k0, T... keys) const {
		if (costs_.empty()) { // extremely common case
			return default_;
		}
		const auto i = costs_.find(k0);
		if (i != costs_.end()) {
			return i->second(keys...);
		} else {
			return default_;
		}
	}
};

template<typename CostType, typename UCharType>
class CostsMap<1, UCharType, CostType> {
	std::vector<CostType> costs_;
	CostType default_;

public:
	CostsMap() : default_(1) {
	}

	bool set(CostType cost, const UCharType *p_k = nullptr) {
		if (!p_k) {
			costs_.clear();
			default_= cost;
			return true;
		} else {
			const UCharType k = *p_k;

			if (k >= costs_.size()) {
				costs_.resize(k + 1, default_);
			}
			costs_[k] = cost;
			return true;
		}
	}

	inline CostType operator()(UCharType k) const {
		if (k < costs_.size()) {
			return costs_[k];
		} else {
			return default_;
		}
	}
};

template<typename CostType>
class Costs {
public:
	CostsMap<1, UCharType, CostType> insert;
	CostsMap<1, UCharType, CostType> delete_;
	CostsMap<2, UCharType, CostType> replace;
	CostsMap<2, UCharType, CostType> transpose;
	CostsMap<3, UCharType, CostType> split;
	CostsMap<3, UCharType, CostType> merge;

	bool set_insert_cost(CostType cost) {
		return insert.set(cost);
	}

	bool set_insert_cost(const UCharType k, CostType cost) {
		return insert.set(cost, &k);
	}

	bool set_delete_cost(CostType cost) {
		return delete_.set(cost);
	}

	bool set_delete_cost(const UCharType k, CostType cost) {
		return delete_.set(cost, &k);
	}

	bool set_replace_cost(const UCharType k1, const UCharType k2, CostType cost) {
		return replace.set(cost, &k1, &k2);
	}

	bool set_transpose_cost(const UCharType k1, const UCharType k2, CostType cost) {
		return transpose.set(cost, &k1, &k2);
	}

	bool set_split_cost(const UCharType a, const UCharType b1, const UCharType b2, CostType cost) {
		return split.set(cost, &a, &b1, &b2);
	}

	bool set_merge_cost(const UCharType a1, const UCharType a2, const UCharType b, CostType cost) {
		return merge.set(cost, &a1, &a2, &b);
	}
};

template<typename T>
class Matrix {
	SizeType columns_;
	std::vector<T> rows_;

public:
	inline void set_columns(SizeType n_columns) {
		columns_ = n_columns;
	}

	inline SizeType columns() const {
		return columns_;
	}

	inline void reserve(SizeType n_rows) {
		rows_.reserve(n_rows * columns_);
	}

	inline const T *operator[](int i) const {
		assert(i >= 0 && ((i + 1) * columns_) <= rows_.size());
		return rows_.data() + i * columns_;
	}

	inline T *operator[](int i) {
		assert(i >= 0 && ((i + 1) * columns_) <= rows_.size());
		return rows_.data() + i * columns_;
	}

	inline T *allocate(int i) {
		rows_.resize((i + 1) * columns_);
		return (*this)[i];
	}
};

template<typename Delegate>
class DFS {
	Delegate &delegate;

	const Dictionary *dic_;
	const Guide *guide_;

	std::stack<BaseType> stack_;
	std::vector<UCharType> key_;

	enum {
		NEXT_SIBLING,
		NEXT_CHILD,
	} state_;

	inline void ascend() {
		delegate.on_ascend();

		stack_.pop();
		key_.pop_back();
	}

	inline bool follow(UCharType label) {
		BaseType index = stack_.top();

		if (!dic_->Follow(label, &index)) {
			return false;
		}

		stack_.push(index);
		key_.push_back(label);
		return true;
	}

public:
	inline DFS(Delegate *delegate) : delegate(*delegate) {
	}

	void set_dic(const Dictionary &dic) {
		dic_ = &dic;
	}
	void set_guide(const Guide &guide) {
		guide_ = &guide;
	}

	inline const std::vector<UCharType> &key() const {
		return key_;
	}
	inline ValueType value() const {
		return dic_->value(stack_.top());
	}

	inline void start(const size_t max_expected_depth) {
		assert(dic_);
		assert(guide_);

		state_ = NEXT_CHILD;
		std::stack<BaseType>().swap(stack_);
		stack_.push(dic_->root());

		key_.clear();
		key_.reserve(max_expected_depth);
	}

	inline bool next() {
		if (stack_.empty()) {
			return false;
		}

		while (true) {
			switch (state_) {
				case NEXT_CHILD: {

					const UCharType child_label = guide_->child(stack_.top());

					if (child_label != '\0') {
						if (!follow(child_label)) {
							return false;
						}

						bool descend, result;
						std::tie(descend, result) =
							delegate.on_step();

						if (!descend) {
							state_ = NEXT_SIBLING;
							if (result) {
								return true;
							}
							break;
						}
						if (result) {
							return true;
						}
					} else {
						state_ = NEXT_SIBLING;
					}
				} break;

				case NEXT_SIBLING: {
					while (true) {
						// visit the next sibling of the current index_, i.e.
						// go up one element in stack and descent to next sibling.

						const UCharType sibling_label = guide_->sibling(stack_.top());

						// get the child off the stack.
						ascend();

						if (sibling_label != '\0') {
							// Follows a transition to the next sibling.
						    if (!follow(sibling_label)) {
								return false;
						    }

							bool descend, result;
							std::tie(descend, result) =
								delegate.on_step();

							if (descend) {
						    	state_ = NEXT_CHILD;
							} else {
								state_ = NEXT_SIBLING;
							}
							if (result) {
								return true;
							}
					    	break;
						} else {
							if (stack_.empty()) {
								return false;
							}
						}
					}
				} break;
			}
		}

		return false;
	}

	inline bool has_value() const {
		return dic_->has_value(stack_.top());
	}
};

class LCS {
	typedef int16_t IndexType;

	DFS<LCS> dfs_;
	std::vector<UCharType> word_;
	Matrix<IndexType> C_;
	IndexType min_length_;
	std::vector<UCharType> result_;

protected:
	friend class DFS<LCS>;

	void backtrack(const UCharType * const a, const UCharType * const b, SizeType i, SizeType j) {
		result_.clear();

		while (i > 0 && j > 0) {
	        if (a[i] == b[j]) {
	            result_.push_back(a[i]);
	            i -= 1;
	            j -= 1;
	        } else {
		        if (C_[i][j - 1] > C_[i - 1][j]) {
			        j -= 1;
		        } else {
			        i -= 1;
		        }
	        }
        }

        std::reverse(result_.begin(), result_.end());
        assert(result_.size() == C_[i][C_.columns() - 1]);
	}

	inline std::tuple<bool, bool> on_step() {
		const int i = dfs_.key().size();
		assert(i >= 1);

		const SizeType columns = C_.columns();
		IndexType *row_i = C_.allocate(i);
		IndexType *row_i_1 = row_i - columns;
		row_i[0] = 0; // C[i,0] = 0

		const UCharType * const a = dfs_.key().data() - 1;
		const UCharType * const b = word_.data() - 1;

		for (SizeType j = 1; j < columns; j++) {
		    if (a[i] == b[j]) {
		        // C[i,j] := C[i-1,j-1] + 1
		        row_i[j] = row_i_1[j - 1] + 1;
		    } else {
		        // C[i,j] := max(C[i,j-1], C[i-1,j])
		        row_i[j] = std::max(row_i[j - 1], row_i_1[j]);
		    }
	    }

	    if (dfs_.has_value()) {
	        const IndexType lcs = row_i[columns - 1];
	        if (lcs >= min_length_) {
	            backtrack(a, b, i, columns - 1);
				return std::make_tuple(true, true);
	        }
	    }

		return std::make_tuple(true, false);
	}

	inline void on_ascend() {
	}

public:
	LCS() : dfs_(this) {
	}

	void set_dic(const Dictionary &dic) {
		dfs_.set_dic(dic);
	}

	void set_guide(const Guide &guide) {
		dfs_.set_guide(guide);
	}

	void start(const char *s, const size_t len, const IndexType min_length = 3) {
		word_.clear();
		word_.insert(word_.begin(), s, s + len);
		result_.reserve(len);

		C_.set_columns(len + 1);
		IndexType *row = C_.allocate(0);
		for (SizeType j = 0; j < C_.columns(); j++) {
			row[j] = 0; // C[0,j] = 0
		}

		dfs_.start(10); // FIXME

		min_length_ = min_length;
	}

	bool next() {
		return dfs_.next();
	}

	// These member functions are available only when next() returns true.
	inline const char *key() const {
		return reinterpret_cast<const char *>(dfs_.key().data());
	}
	inline SizeType key_length() const {
		return dfs_.key().size();
	}
	inline ValueType value() const {
		return dfs_.value();
	}
	inline const char *lcs() const {
		return reinterpret_cast<const char *>(result_.data());
	}
	inline SizeType lcs_length() const {
		return result_.size();
	}
};

template<typename CostType>
class Similar {
	DFS<Similar> dfs_;

	const Costs<CostType> *costs_;
	std::vector<CostType> cached_insert_cost_;
	std::unique_ptr<Costs<CostType>> default_costs_;

	std::vector<UCharType> word_;
	Matrix<CostType> distances_;
	CostType max_cost_;
	CostType found_cost_;

	struct {
		unsigned transpose : 1;
		unsigned split : 1;
		unsigned merge : 1;
	} allow_;

	std::vector<BaseType> da_;
	std::vector<BaseType> da_rollback_;

	// col_delete_range_cost taken and row_insert_range_cost are from:
	// https://github.com/infoscout/weighted-levenshtein/
	//     blob/master/weighted_levenshtein/clev.pyx
	inline CostType col_delete_range_cost(int start, int end) const {
		return distances_[end][0] - distances_[start - 1][0];
	}

	inline CostType row_insert_range_cost(int start, int end) const {
		const CostType * const r = distances_[0];
		assert(start >= 1 && end < distances_.columns());
		return r[end] - r[start - 1];
	}

	template<bool Transpose, bool UnionSplit>
	inline std::tuple<bool, bool> compute_cost_fast() {
		const int i = dfs_.key().size();
		assert(i >= 1);

		const UCharType * const a = dfs_.key().data() - 1;
		const UCharType * const b = word_.data() - 1;
	    const UCharType a_i = a[i];

		const auto &costs = *costs_;
		const CostType delete_cost_a_i = costs.delete_(a_i);
		const CostType * const insert_cost_b = cached_insert_cost_.data() - 1;

		const SizeType columns = distances_.columns();
		CostType *row_i = distances_.allocate(i);
		const CostType *row_i_1 = row_i - columns;

		row_i[0] = row_i_1[0] + delete_cost_a_i; // d[i, 0]

		SizeType db = 0;
		CostType row_i_j_1 = row_i[0]; // always row[i][j - 1]
		CostType smallest = row_i_j_1;

		for (SizeType j = 1; j < columns; j++) {
			const UCharType b_j = b[j];

			CostType cost;
			const SizeType L = db;

			CostType replace_cost = row_i_1[j - 1];
			if (b_j != a_i) {
				replace_cost += costs.replace(a_i, b_j);

				const CostType insert_cost = row_i_j_1 + insert_cost_b[j];
				const CostType delete_cost = row_i_1[j] + delete_cost_a_i;

				cost = std::min(
					 std::min(insert_cost, delete_cost), replace_cost);
			} else {
				cost = replace_cost;

				if (Transpose) {
					db = j;
				}
			}

            if (Transpose && L >= 1) {
				const SizeType k = da_[b_j];

                if (k < 1 || L < 1) { // d[−1, _] || d[_, −1] ?
	                // ignore
                } else {
                    const CostType *row_k_1 = distances_[k - 1];

                    const CostType c_diag = row_k_1[L - 1]; // d[k - 1, l - 1]

                    const CostType c0 = costs.transpose(a[k], a[i]);

	                const CostType transpose_cost =
	                    c_diag +
	                    col_delete_range_cost(k + 1, i - 1) +
	                    c0 +
	                    row_insert_range_cost(L + 1, j - 1);

	                cost = std::min(cost, transpose_cost);
                }
            }

            if (UnionSplit && allow_.split && j > 1) {
				const CostType split_cost = row_i_1[j - 2] + costs.split(a[i], b[j - 1], b[j]);
                cost = std::min(cost, split_cost);
            }

            if (UnionSplit && allow_.merge && i > 1) {
				const CostType *row_i_2 = distances_[i - 2];
				const CostType merge_cost = row_i_2[j - 1] + costs.merge(a[i - 1], a[i], b[j]);
                cost = std::min(cost, merge_cost);
            }

			row_i[j] = cost;
			row_i_j_1 = cost;

			smallest = std::min(smallest, cost);
		}

		if (Transpose) {
			da_rollback_.resize(i + 1);
			da_rollback_[i] = da_[a_i];
			da_[a_i] = i;
		}

		const CostType best_cost = row_i[columns - 1];
		const bool descend = (smallest <= max_cost_); // descend further?
		if (best_cost <= max_cost_ && dfs_.has_value()) {
			found_cost_ = best_cost;
			return std::make_tuple(descend, true);
		} else {
			found_cost_ = -1;
			return std::make_tuple(descend, false);
		}
	}

protected:
	friend class DFS<Similar>;

	inline std::tuple<bool, bool> on_step() {
		 if (allow_.split || allow_.merge) {
		    if (allow_.transpose) {
		        return compute_cost_fast<true, true>();
		    } else {
		        return compute_cost_fast<false, true>();
		    }
		 } else if (allow_.transpose) {
		    return compute_cost_fast<true, false>();
		 } else {
		    return compute_cost_fast<false, false>();
		 }
	}

	inline void on_ascend() {
		if (allow_.transpose) {
			const int i = dfs_.key().size();
			assert(i >= 1);
			const UCharType * const a = dfs_.key().data() - 1;
		    da_[a[i]] = da_rollback_[i];
		}
	}


public:
	Similar() : dfs_(this), costs_(nullptr) {

		allow_.transpose = 0;
		allow_.split = 0;
		allow_.merge = 0;
	}

	void set_dic(const Dictionary &dic) {
		dfs_.set_dic(dic);
	}

	void set_guide(const Guide &guide) {
		dfs_.set_guide(guide);
	}

	void set_costs(const Costs<CostType> &costs) {
		costs_ = &costs;
	}

	// These member functions are available only when next() returns true.
	inline const char *key() const {
		return reinterpret_cast<const char *>(dfs_.key().data());
	}
	inline SizeType key_length() const {
		return dfs_.key().size();
	}
	inline ValueType value() const {
		return dfs_.value();
	}
	inline CostType cost() const {
		return found_cost_;
	}

	inline void set_enable_transpose(bool allow) {
		// this enables real Damerau-Levenshtein distances with adjacent transpositions,
		// see https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
		allow_.transpose = allow;
	}

	inline void set_enable_merge(bool allow) {
		allow_.merge = allow;
	}

	inline void set_enable_split(bool allow) {
		allow_.split = allow;
	}

	void start(const char *s, const size_t len, const CostType max_cost = 0) {
		word_.clear();
		word_.insert(word_.begin(), s, s + len);

		if (!costs_) {
			default_costs_.reset(new Costs<CostType>());
			costs_ = default_costs_.get();
		}

		distances_.set_columns(len + 1);
		found_cost_ = -1;

		max_cost_ = std::max(CostType(0), max_cost);
		const int max_expected_depth = len * 2 + 1;

		dfs_.start(max_expected_depth);

		distances_.reserve(max_expected_depth);
		cached_insert_cost_.resize(len);
		CostType *row_0 = distances_.allocate(0);
		CostType cost = 0;
		row_0[0] = 0;
		const SizeType columns = distances_.columns();
		for (SizeType j = 1; j < columns; j++) {
			const CostType ic = costs_->insert(word_[j - 1]);
			cached_insert_cost_[j - 1] = ic;
			cost += ic;
			row_0[j] = cost; // d[0, j]
		}

		if (allow_.transpose) {
			assert(sizeof(UCharType) == 8);
			da_.clear();
			da_.resize(std::numeric_limits<UCharType>::max() + 1, 0);
			da_rollback_.reserve(max_expected_depth);
		}
	}

	bool next() {
		return dfs_.next();
	}
};

}

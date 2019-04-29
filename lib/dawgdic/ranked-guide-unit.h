#ifndef DAWGDIC_RANKED_GUIDE_UNIT_H
#define DAWGDIC_RANKED_GUIDE_UNIT_H

#include "base-types.h"

namespace dawgdic {

class RankedGuideUnit {
 public:
  RankedGuideUnit() : child_('\0'), sibling_('\0') {}

  void set_child(UCharType child) {
    child_ = child;
  }
  void set_sibling(UCharType sibling) {
    sibling_ = sibling;
  }

  UCharType child() const {
    return child_;
  }
  UCharType sibling() const {
    return sibling_;
  }

 private:
  UCharType child_;
  UCharType sibling_;

  // Copyable.
};

}  // namespace dawgdic

#endif  // DAWGDIC_RANKED_GUIDE_UNIT_H

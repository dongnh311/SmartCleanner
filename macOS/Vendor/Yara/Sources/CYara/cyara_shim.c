#include <yara.h>
#include "cyara_shim.h"

const char* cyara_rule_identifier(const void* rule)
{
  return ((const YR_RULE*) rule)->identifier;
}

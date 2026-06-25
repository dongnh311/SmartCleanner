#ifndef CYARA_SHIM_H
#define CYARA_SHIM_H
// Tiny helpers so Swift doesn't have to reach into YARA's DECLARE_REFERENCE
// anonymous unions. Take void* to avoid importing the structs on the Swift side.
const char* cyara_rule_identifier(const void* rule);
#endif

include ../adm/root.mk
include $(MFEXT_HOME)/share/subdir_root.mk

test:
	layer_wrapper --layers=devtools@mfext noutf8.sh

all:: $(MFMODULE_HOME)/lib/tbs.lua

$(MFMODULE_HOME)/lib/tbs.lua: tbs.lua
	@mkdir -p "$(MFMODULE_HOME)/lib"
	layer_wrapper --layers=devtools@mfext -- test_globals_in_lua.sh $<
	cp -f $< $@

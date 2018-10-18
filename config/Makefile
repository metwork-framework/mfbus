CONFIGS=config.ini redis.conf circus.ini nginx.conf tmp_blob_store.lua

include ../adm/root.mk
include $(MFEXT_HOME)/share/subdir_root.mk
include $(MFCOM_HOME)/share/config_subdir.mk

all:: $(MODULE_HOME)/config/telegraf.conf $(MODULE_HOME)/config/circus.ini

test::
	layer_wrapper --layers=devtools@mfext -- test_globals_in_lua.sh *.lua

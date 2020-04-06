CONFIGS=config.ini nginx.conf mflog_override.conf rabbitmq.conf enabled_plugins

include ../adm/root.mk
include $(MFEXT_HOME)/share/subdir_root.mk
include $(MFEXT_HOME)/share/config_subdir.mk

all:: $(MFMODULE_HOME)/config/circus.ini $(MFMODULE_HOME)/config/telegraf.conf

BINS=_check_circus_conf rabbitmq_wrapper before_start_rabbitmq rabbitmq.status before_signal get_epmd_pid

include root.mk
include $(MFEXT_HOME)/share/subdir_root.mk
include $(MFEXT_HOME)/share/startup_scripts_profiles.mk

all:: profiles $(PREFIX)/bin/cronwrap.sh $(PREFIX)/bin/mfbus.status $(PREFIX)/bin/mfbus.start $(PREFIX)/bin/mfbus.stop $(PREFIX)/bin/mfbus.init load_env

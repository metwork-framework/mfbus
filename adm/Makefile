BINS=_check_nginx_conf _check_circus_conf rabbitmq_wrapper before_start_rabbitmq check_rabbitmq_status.py before_signal get_epmd_pid fake.sh

include root.mk
include $(MFEXT_HOME)/share/subdir_root.mk
include $(MFEXT_HOME)/share/startup_scripts_profiles.mk

all:: profiles $(PREFIX)/bin/cronwrap.sh $(PREFIX)/bin/mfbus.status $(PREFIX)/bin/mfbus.start $(PREFIX)/bin/mfbus.stop $(PREFIX)/bin/mfbus.init load_env

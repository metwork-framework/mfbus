MODULE=MFBUS
MODULE_LOWERCASE=mfbus

-include adm/root.mk
-include $(MFEXT_HOME)/share/main_root.mk

all:: directories
	echo "root@mfcom" >$(MFBUS_HOME)/.layerapi2_dependencies
	cd adm && $(MAKE)
	cd config && $(MAKE)

clean::
	cd config && $(MAKE) clean
	cd adm && $(MAKE) clean

directories:
	@for DIR in config bin; do mkdir -p $(MFBUS_HOME)/$$DIR; done

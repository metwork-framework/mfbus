# How to install/upgrade/remove mfbus metwork module (with internet access)

[//]: # (automatically generated from https://github.com/metwork-framework/resources/blob/master/cookiecutter/_%7B%7Bcookiecutter.repo%7D%7D/.metwork-framework/install_a_metwork_package.md)

## Prerequisites

You must:

- have configured the metwork yum repository. Please see [the corresponding document](configure_metwork_repo.md) document to do that.
- have an internet access on this computer

## Install mfbus metwork module

## Full installation

You just have to execute the following command (as `root` user):

```bash
yum install metwork-mfbus
```

## Minimal installation

If you prefer to start with a minimal installation, you have to execute the following command
(as `root` user):

```bash
yum install metwork-mfbus-minimal
```

## Optional Addons

### Optional dependencies addons

```bash
# To install some devtools
yum install metwork-mfext-layer-python3_devtools

# To install some scientific libraries
yum install metwork-mfext-layer-python3_scientific

# To install python2 support
# (including corresponding scientific and devtools addons)
yum install metwork-mfext-layer-python2
yum install metwork-mfext-layer-python2_scientific
yum install metwork-mfext-layer-python2_devtools
```





## Services

You can start corresponding services with the root command:

```bash
service metwork start
```

Or you can also reboot your computer (because metwork services are started automatically on boot).



## Uninstall mfbus metwork module


To uninstall mfbus metwork module, please stop corresponding metwork services with the `root` command:

```bash
service metwork stop mfbus
```

Then, use the following command (still as `root` user):


```bash
yum remove "metwork-mfbus*"
```

## Upgrade mfbus metwork module

To upgrade mfbus metwork module, use the following commands (still as `root` user):


```bash
# We stop mfbus services
service metwork stop mfbus
```


```bash
# We upgrade mfbus metwork module
yum upgrade "metwork-mfbus*"
```


```bash
# We start mfbus services
service metwork start mfbus
```


## Uninstall all metwork modules

To uninstall all metwork modules, use following root commands:

```bash
# We stop metwork services
service metwork stop

# we remove metwork modules
yum remove "metwork-*"
```

## Upgrade all metwork modules

The same idea applies to upgrade.

For example, to upgrade all metwork modules on a computer, use following root commands:

```bash
# We stop metwork services
service metwork stop

# We upgrade metwork modules
yum upgrade "metwork-*"

# We start metwork services
service metwork start
```

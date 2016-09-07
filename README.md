# admin_scripts

### mexternal

* rewrite of mbackup

### addPath.rb 

* update bash PATH, possibly moving existing entries

Example,

```
$ export PATH=$(addPath.rb -p ~/bin)
```

### mbackup

* script to mount encrypted backup and run post mount script(s)

### mondir

* script to monitor directory heirarchy for changes


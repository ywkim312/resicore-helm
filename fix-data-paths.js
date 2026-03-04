// Fix path mismatch: MongoDB dataURL uses subdir (e.g. 5c/64/5c64964fc11bb380da598adc/file.tif)
// but files were migrated to parent dir (5c/64/file.tif). Creates symlinks so both paths work.
// Output: shell script - pipe to fix-paths.sh
print('#!/bin/sh');
print('set -e');
print('cd /home/incore/data || exit 1');

var datadb = db.getSiblingDB('datadb');
var base = '/home/incore/data';
var seen = {};

datadb.Dataset.find({}, {fileDescriptors: 1}).forEach(function(ds) {
  (ds.fileDescriptors || []).forEach(function(fd) {
    if (!fd.dataURL || fd.deleted) return;
    var fullPath = fd.dataURL.replace(/^\/home\/incore\/data\/?/, '').replace(/^\//, '');
    var dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
    var file = fullPath.substring(fullPath.lastIndexOf('/') + 1);
    if (!dir || !file) return;
    var parts = dir.split('/');
    if (parts.length < 3) return;
    var key = dir + '/' + file;
    if (seen[key]) return;
    seen[key] = true;
    print('mkdir -p "' + base + '/' + dir + '" && ln -sf "../' + file + '" "' + base + '/' + dir + '/' + file + '" 2>/dev/null || true');
  });
});

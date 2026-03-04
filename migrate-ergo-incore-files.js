// Run on incore-prod MongoDB (READ-ONLY) to get list of data paths for ergo/incore records
// Output: paths to copy from /home/incore/data
// Usage: Get-Content migrate-ergo-incore-files.js | kubectl exec -i incore-mongodb-0 -n incore --context incore-prod -- mongo admin --quiet
// (Or use mongosh if available; adjust auth as needed)

var datadb = db.getSiblingDB('datadb');
var hazarddb = db.getSiblingDB('hazarddb');

// 1. Get Dataset IDs we keep (from datadb.Space ergo/incore members)
var keepDatasetIds = {};
datadb.Space.find({'metadata.name': {$in: ['ergo','incore']}}).forEach(function(space) {
  (space.members || []).forEach(function(mid) { keepDatasetIds[String(mid)] = true; });
});

// 2. Get datasetIds referenced by hazard docs we keep (creator/owner ergo|incore)
var hazardDatasetIds = {};
['TsunamiDataset','TornadoModel','EarthquakeDataset','EarthquakeModel','HurricaneDataset','FloodDataset','TornadoDataset','ScenarioTornado','HurricaneWindfields','ScenarioEarthquake'].forEach(function(c) {
  hazarddb.getCollection(c).find({$or: [{creator: {$in: ['ergo','incore']}}, {owner: {$in: ['ergo','incore']}}]}).forEach(function(h) {
    if (h.hazardDatasets) {
      h.hazardDatasets.forEach(function(hd) {
        if (hd.datasetId) hazardDatasetIds[String(hd.datasetId)] = true;
      });
    }
  });
});

// Merge: we need files for keepDatasetIds + hazardDatasetIds (hazard refs may be in datadb)
var allIds = Object.assign({}, keepDatasetIds, hazardDatasetIds);

// 3. Get dataURL paths from Datasets (only those we need)
var ids = Object.keys(allIds).filter(function(k){ return /^[a-f0-9]{24}$/i.test(k); });
var pathsToCopy = {};
datadb.Dataset.find({_id: {$in: ids.map(function(k){ return ObjectId(k); })}}).forEach(function(ds) {
  if (!ds.fileDescriptors) return;
  ds.fileDescriptors.forEach(function(fd) {
    if (!fd.dataURL || fd.deleted) return;
    var dir = fd.dataURL.substring(0, fd.dataURL.lastIndexOf('/'));
    if (dir) pathsToCopy[dir] = true;
  });
});

// Output: one path per line (relative to /home/incore/data)
Object.keys(pathsToCopy).sort().forEach(function(p) { print(p); });

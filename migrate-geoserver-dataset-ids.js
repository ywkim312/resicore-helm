// Output dataset IDs for ergo/incore - use for GeoServer layer migration (layer name = dataset id)
// Run on incore-prod: cat migrate-geoserver-dataset-ids.js | kubectl exec -i incore-mongodb-0 -n incore --context incore-prod -- mongo "mongodb://root:PASSWORD@localhost:27017/admin" --quiet > geoserver-dataset-ids.txt

var datadb = db.getSiblingDB('datadb');
var hazarddb = db.getSiblingDB('hazarddb');

var keepDatasetIds = {};
datadb.Space.find({'metadata.name': {$in: ['ergo','incore']}}).forEach(function(space) {
  (space.members || []).forEach(function(mid) { keepDatasetIds[String(mid)] = true; });
});

['TsunamiDataset','TornadoModel','EarthquakeDataset','EarthquakeModel','HurricaneDataset','FloodDataset','TornadoDataset','ScenarioTornado','HurricaneWindfields','ScenarioEarthquake'].forEach(function(c) {
  hazarddb.getCollection(c).find({$or: [{creator: {$in: ['ergo','incore']}}, {owner: {$in: ['ergo','incore']}}]}).forEach(function(h) {
    if (h.hazardDatasets) {
      h.hazardDatasets.forEach(function(hd) {
        if (hd.datasetId) keepDatasetIds[String(hd.datasetId)] = true;
      });
    }
  });
});

var ids = Object.keys(keepDatasetIds).filter(function(k){ return /^[a-f0-9]{24}$/i.test(k); });
ids.sort().forEach(function(id) { print(id); });

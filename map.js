// Initialize the map
var map = L.map('map').setView([0, 0], 2);

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 21
}).addTo(map);

// Marker clusters and search layer
var clusterGroup = L.markerClusterGroup({ disableClusteringAtZoom: 17 });
var searchLayer = L.layerGroup(); // for search control

// Load CSV and populate markers
Papa.parse('data.csv', {
  download: true,
  header: true,
  skipEmptyLines: true,
  complete: function(results) {
    results.data.forEach(function(row) {
      if (row.Name && row.Latitude && row.Longitude) {
        var name = row.Name.trim();
        var lat = parseFloat(row.Latitude);
        var lng = parseFloat(row.Longitude);

        if (!isNaN(lat) && !isNaN(lng)) {
          var marker = L.marker([lat, lng], {
            title: name // REQUIRED for search to work
          }).bindPopup('<strong>' + name + '</strong>');

          clusterGroup.addLayer(marker);
          searchLayer.addLayer(marker);
        }
      }
    });

    map.addLayer(clusterGroup);

    if (clusterGroup.getLayers().length > 0) {
      map.fitBounds(clusterGroup.getBounds());
    }

    // ✅ Add search control AFTER markers are loaded
    var searchControl = new L.Control.Search({
      layer: searchLayer,
      propertyName: 'title',
      marker: false,
      textPlaceholder: 'Search by name...',
      moveToLocation: function(latlng, title, map) {
        map.setView(latlng, 18);
      }
    });

    searchControl.on('search:locationfound', function(e) {
      e.layer.openPopup();
    });

    map.addControl(searchControl);
  }
});

// Add "Locate Me" button
L.control.locate({
  position: 'topleft',
  strings: {
    title: "Show me where I am"
  },
  flyTo: true
}).addTo(map);

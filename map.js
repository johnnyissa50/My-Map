var map = L.map('map').setView([0, 0], 2);

// Base tile
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 21
}).addTo(map);

// Marker clusters and search layer
var clusterGroup = L.markerClusterGroup({ disableClusteringAtZoom: 17 });
var searchLayer = L.layerGroup();

// Load CSV
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
          var marker = L.marker([lat, lng], { title: name })
            .bindPopup('<strong>' + name + '</strong>');

          clusterGroup.addLayer(marker);
          searchLayer.addLayer(marker);
        }
      }
    });

    map.addLayer(clusterGroup);
    map.addLayer(searchLayer);

    if (clusterGroup.getLayers().length > 0) {
      map.fitBounds(clusterGroup.getBounds());
    }

    // Add search control
    var searchControl = new L.Control.Search({
      layer: searchLayer,
      propertyName: 'title',
      marker: false,
      moveToLocation: function(latlng) {
        map.setView(latlng, 18);
      }
    });

    searchControl.on('search:locationfound', function(e) {
      e.layer.openPopup();
    });

    map.addControl(searchControl);
  }
});

// Add GPS locate button
L.control.locate({
  position: 'topleft',
  strings: {
    title: "Show my location"
  },
  flyTo: true
}).addTo(map);

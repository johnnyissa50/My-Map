// Initialize the map
var map = L.map('map').setView([0, 0], 2);

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Create a marker cluster group for clustering markers
var clusterGroup = L.markerClusterGroup({ disableClusteringAtZoom: 17 });

// Create a layer group for search (separate from cluster)
var searchLayer = L.layerGroup();

// Load and parse CSV data
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

                // Create marker with 'title' property for search
                var marker = L.marker([lat, lng], { title: name })
                    .bindPopup('<strong>' + name + '</strong>');

                clusterGroup.addLayer(marker);
                searchLayer.addLayer(marker);
            }
        });

        // Add cluster group to map
        map.addLayer(clusterGroup);

        // Fit map bounds to markers
        if (clusterGroup.getLayers().length > 0) {
            map.fitBounds(clusterGroup.getBounds());
        }

        // Add Leaflet Search control
        var searchControl = new L.Control.Search({
            layer: searchLayer,
            propertyName: 'title',
            marker: false,
            textPlaceholder: 'Search points by name...',
            moveToLocation: function(latlng, title, map) {
                map.setView(latlng, 18); // zoom when found
            }
        });

        searchControl.on('search:locationfound', function(e) {
            e.layer.openPopup();
        });

        map.addControl(searchControl);
    }
});

// Add Locate Me control button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true
}).addTo(map);

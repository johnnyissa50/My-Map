// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add base layer
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Create cluster and searchable layers
var clusterGroup = L.markerClusterGroup({ disableClusteringAtZoom: 17 });
var searchLayer = L.layerGroup(); // Used ONLY for search

// Load CSV
Papa.parse('data.csv', {
    download: true,
    header: true,
    skipEmptyLines: true,
    complete: function(results) {
        results.data.forEach(function(row) {
            if (row.Latitude && row.Longitude && row.Name) {
                var lat = parseFloat(row.Latitude);
                var lng = parseFloat(row.Longitude);
                var name = row.Name.trim(); // 🔍 Remove extra spaces

                // Create marker
                var marker = L.marker([lat, lng], { title: name }) // title used for search
                    .bindPopup('<strong>' + name + '</strong>');

                clusterGroup.addLayer(marker);
                searchLayer.addLayer(marker); // 🔍 Add to search layer
            }
        });

        map.addLayer(clusterGroup);
        map.fitBounds(clusterGroup.getBounds());

        // Add Search Control
        var searchControl = new L.Control.Search({
            layer: searchLayer,
            propertyName: 'title',   // 🔍 Looks in marker.options.title
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

// Optional: Geocoder for cities/places
L.Control.geocoder({
    defaultMarkGeocode: false
}).on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
}).addTo(map);

// Add "Locate Me" GPS button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true
}).addTo(map);

// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add base map
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Cluster group and search markers list
var markers = L.markerClusterGroup({ disableClusteringAtZoom: 17 });
var markerList = [];

Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude && point.Name) {
                var lat = parseFloat(point.Latitude);
                var lng = parseFloat(point.Longitude);
                var name = point.Name;

                var marker = L.marker([lat, lng]);
                marker.bindPopup('<strong>' + name + '</strong>');
                marker.options.title = name; // Required for search

                markers.addLayer(marker);
                markerList.push(marker);
            }
        });

        map.addLayer(markers);
        map.fitBounds(markers.getBounds());

        // ✅ Local Search with Suggestions (case-sensitive)
        var searchControl = new L.Control.Search({
            layer: L.layerGroup(markerList),
            propertyName: 'title',
            textPlaceholder: 'Search by name...',
            textSearch: true, // 🔍 Enables suggestions
            marker: false,
            moveToLocation: function(latlng, title, map) {
                map.setView(latlng, 18);
            },
            // ✅ Custom filter: case-sensitive search
            filterData: function(text, records) {
                var results = {};
                for (var key in records) {
                    if (key.includes(text)) {
                        results[key] = records[key];
                    }
                }
                return results;
            }
        });

        searchControl.on('search:locationfound', function(e) {
            e.layer.openPopup();
        });

        map.addControl(searchControl);
    }
});

// Optional: Global geocoder
L.Control.geocoder({
    defaultMarkGeocode: false
})
.on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
})
.addTo(map);

// Locate me button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true
}).addTo(map);

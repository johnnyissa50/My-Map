// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Cluster group and search layer
var markers = L.markerClusterGroup({ disableClusteringAtZoom: 17 });
var markerList = []; // Used only for search (non-clustered layer)

Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude && point.Name) {
                var lat = parseFloat(point.Latitude);
                var lng = parseFloat(point.Longitude);
                var name = point.Name;

                // Create marker
                var marker = L.marker([lat, lng]);
                marker.bindPopup('<strong>' + name + '</strong>');
                marker.options.title = name; // Required for search

                markers.addLayer(marker);
                markerList.push(marker);
            }
        });

        map.addLayer(markers);
        map.fitBounds(markers.getBounds());

        // ✅ SEARCH FIXED HERE
        var searchControl = new L.Control.Search({
            layer: L.layerGroup(markerList), // Search separate layer
            propertyName: 'title',           // Matches marker.options.title
            marker: false,
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

// Optional geocoder for places
L.Control.geocoder({
    defaultMarkGeocode: false
}).on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
}).addTo(map);

// Locate me button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true
}).addTo(map);

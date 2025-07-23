// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18
}).addTo(map);

// Initialize marker cluster group with clustering disabled at zoom 15+
var markers = L.markerClusterGroup({
    disableClusteringAtZoom: 15
});

// Function to load and parse CSV
Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude) {
                var marker = L.marker([parseFloat(point.Latitude), parseFloat(point.Longitude)])
                    .bindPopup('<strong>' + point.Name + '</strong>');
                marker.feature = { properties: { name: point.Name } };  // for search
                markers.addLayer(marker);
            }
        });
        map.addLayer(markers);
        map.fitBounds(markers.getBounds());
    }
});

// Add search control
L.Control.geocoder({
    defaultMarkGeocode: false
})
.on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
})
.addTo(map);

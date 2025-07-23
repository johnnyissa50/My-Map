// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Initialize marker cluster group (disable clustering at zoom 17+)
var markers = L.markerClusterGroup({
    disableClusteringAtZoom: 17
});

// Load and parse CSV file
Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude) {
                var marker = L.marker([parseFloat(point.Latitude), parseFloat(point.Longitude)])
                    .bindPopup('<strong>' + point.Name + '</strong>');
                marker.feature = { properties: { name: point.Name } }; // for potential search extension
                markers.addLayer(marker);
            }
        });
        map.addLayer(markers);
        map.fitBounds(markers.getBounds());
    }
});

// Add search control (geocoder)
L.Control.geocoder({
    defaultMarkGeocode: false
})
.on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
})
.addTo(map);

// Add Locate Me (GPS) button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true,
    keepCurrentZoomLevel: false,
    showPopup: false
}).addTo(map);

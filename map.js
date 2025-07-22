
// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add OpenStreetMap tiles
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18
}).addTo(map);

// Add GPS locate button
L.control.locate().addTo(map);

// Initialize marker cluster group
var markers = L.markerClusterGroup();
var searchLayer = [];

// Load CSV data
Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude) {
                var marker = L.marker([parseFloat(point.Latitude), parseFloat(point.Longitude)])
                    .bindPopup('<strong>' + point.Name + '</strong>');

                marker.feature = { properties: { name: point.Name } }; // for search
                markers.addLayer(marker);
                searchLayer.push(marker);
            }
        });

        map.addLayer(markers);
        map.fitBounds(markers.getBounds());

        // Initialize search control
        var searchControl = new L.Control.Search({
            layer: L.layerGroup(searchLayer),
            propertyName: 'name',
            marker: false,
            moveToLocation: function(latlng, title, map) {
                map.setView(latlng, 15);
            }
        });

        map.addControl(searchControl);
    }
});

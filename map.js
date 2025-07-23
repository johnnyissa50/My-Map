// Initialize map
var map = L.map('map').setView([0, 0], 2);

// Add base map
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 21
}).addTo(map);

// Initialize marker cluster group
var markers = L.markerClusterGroup({
    disableClusteringAtZoom: 17
});

var markerList = []; // Store individual markers for search

// Load and parse CSV
Papa.parse('data.csv', {
    download: true,
    header: true,
    complete: function(results) {
        results.data.forEach(function(point) {
            if (point.Latitude && point.Longitude && point.Name) {
                var lat = parseFloat(point.Latitude);
                var lng = parseFloat(point.Longitude);
                var name = point.Name;

                var marker = L.marker([lat, lng])
                    .bindPopup('<strong>' + name + '</strong>');

                marker.options.title = name; // Needed for Leaflet Search
                markerList.push(marker);
                markers.addLayer(marker);
            }
        });

        map.addLayer(markers);
        map.fitBounds(markers.getBounds());

        // Add local search control (by name)
        var searchControl = new L.Control.Search({
            layer: L.layerGroup(markerList),
            propertyName: 'title',
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

// Optional: Add global geocoder (e.g., places, cities)
L.Control.geocoder({
    defaultMarkGeocode: false
})
.on('markgeocode', function(e) {
    map.setView(e.geocode.center, 10);
})
.addTo(map);

// Add Locate button
L.control.locate({
    position: 'topleft',
    strings: {
        title: "Show my location"
    },
    flyTo: true,
    keepCurrentZoomLevel: false,
    showPopup: false
}).addTo(map);

import QtQuick

// MockMedia — stands in for the hub's MprisBridge inside the Manager clone, so
// MediaWidget renders. The Manager isn't a media controller; this just shows a
// representative "nothing playing" state.
QtObject {
    property bool available: false
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property string status: "Stopped"
    property bool playing: false
    property string playerName: ""
    property real position: 0.0
    function playPause() {}
    function next() {}
    function previous() {}
}

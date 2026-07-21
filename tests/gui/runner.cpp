#include <QtQuickTest/quicktest.h>

// The asset .qrc files are linked into this executable by CMake. Their generated
// static initializers register the same qrc:/icons, qrc:/wallpapers and
// qrc:/fonts trees used by the shipped Hub and Manager. Product QML itself is
// intentionally loaded from the signed source-tree imports selected by the test
// runner; packaged qrc:/qml startup is covered by the real-binary smoke tests.
// Stock qmltestrunner has none of the asset resources, which made compositor
// pixel tests compare blank/missing images while claiming to exercise the UI.
QUICK_TEST_MAIN(xeneon_gui)

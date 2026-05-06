import QtQuick
import QtQuick.Layouts
import QmlEase
import QmlEase.Visual

Window {
    id: root
    width: 800
    height: 480

    property string leftSourceName: 'likianta-home-pc'
    property string rightSourceName: 'likianta-oneplus-11'
    property bool   _debugLayout: false

    Vertical {
        anchors {
            fill: parent
            margins: 12
        }
        placeItemsStart: true
        showBorder: root._debugLayout

        Horizontal {
            Layout.fillWidth: true
            showBorder: root._debugLayout

            TextInput {
                id: leftInput
                Layout.fillWidth: true
                // Layout.fillHeight: false
                enabled: false
                label: 'Left source'
                text: root.leftSourceName
            }

            TextInput {
                id: rightInput
                Layout.fillWidth: true
                // Layout.fillHeight: false
                label: 'Right source'
                outlineColor: pycolor.theme_blue
                text: root.rightSourceName
            }

            // Component.onCompleted: {
            //     py.qmlease.inspect_size(leftInput)
            //     py.qmlease.inspect_size(rightInput)
            // }
        }

        RadioGroup {
            Layout.fillWidth: true
            label: 'Select working item'
            model: [
                'gitbook-source-docs',
                'pictures',
                'video-short',
                'new...'
            ]
        }
//        Horizontal {
//            Layout.fillWidth: true
//            RadioGroup {
//                // Layout.fillWidth: true
//                // Layout.preferredWidth:
//                label: 'Select working item'
//                model: [
//                    'gitbook-source-docs',
//                    'pictures',
//                    'video-short',
//                    'new...'
//                ]
//            }
//            Vertical {
//                Layout.fillWidth: true
//                Layout.fillHeight: true
//                showBorder: true
//                Text {
//                    ''
//                }
//            }
//        }

        Info {
            Layout.fillWidth: true
            text: `📁 ${root.leftSourceName}\n\n📁 ${root.rightSourceName}`
            type: 'info'
        }

        Horizontal {
            Layout.fillWidth: true
            placeItemsStart: true
            Button {
                text: 'Update left'
            }
            Button {
                text: 'Update right'
            }
            Button {
                // border.color: pycolor.get(pycolor.theme_blue, 'outline_variant')
                color: pycolor.get(pycolor.theme_blue, 'darker')
                text: 'Sync'
                // textColor: pycolor.on_theme_blue
            }
            Button {
                text: 'Merge'
                onClicked: {
                    pycolor.dark_theme = !pycolor.dark_theme  // TEST
                }
            }
        }
    }
}

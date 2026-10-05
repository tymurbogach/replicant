import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../replicant.js" as R

// Every plugin, at the top of the Plugins card. The file rows under it are
// only the plugins with a settings file of their own, so eight plugins used
// to show as three. Most keep their settings in shell.json, which the
// Desktop & bar area saves. A restore installs none of them on its own: the
// Restore tab offers each one that is not here.
Column {
  id: pv
  // The panel this belongs to. Every value and every action comes from it.
  property var panel
  readonly property var plugins: R.pluginRows(panel.repoState)
  readonly property int nInstalled: pv.plugins.filter(function(p) { return p.installed }).length
  spacing: 0

  CardLabel {
    panel: pv.panel
    text: R.plural(pv.nInstalled, "plugin") + " installed"
          + (pv.plugins.length > pv.nInstalled ? ", " + (pv.plugins.length - pv.nInstalled) + " on other machines only" : "")
  }
  Repeater {
    model: pv.plugins
    delegate: ListRow {
      required property var modelData
      panel: pv.panel
      width: pv.width
      icon: panel.icPlugin
      iconColor: modelData.installed ? Color.accent : panel.dim
      title: modelData.name
      titleColor: modelData.installed ? panel.fg : panel.dim
      detail: R.pluginDetail(modelData)
      detailColor: modelData.installed && !modelData.recorded ? Color.accent : panel.dim
      meta: R.pluginWhere(modelData)
      metaColor: !modelData.installed ? panel.warnColor : modelData.settings === "file" ? panel.fg : panel.dim
    }
  }
  CardLabel {
    panel: pv.panel
    text: "Their own settings files"
    visible: pv.plugins.some(function(p) { return p.settings === "file" })
  }
}

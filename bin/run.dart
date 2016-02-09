import "package:dslink/dslink.dart";

import "dart:async";
import "dart:io";

import "package:vm_service/service_io.dart";

LinkProvider link;

/// An Action for Deleting a Given Node
class DeleteActionNode extends SimpleNode {
  final String targetPath;

  /// When this action is invoked, [provider.removeNode] will be called with [targetPath].
  DeleteActionNode(String path, SimpleNodeProvider provider, this.targetPath) : super(path, provider);

  /// When this action is invoked, [provider.removeNode] will be called with the parent of this action.
  DeleteActionNode.forParent(String path, SimpleNodeProvider provider)
      : this(path, provider, new Path(path).parentPath);

  /// Handles an action invocation and deletes the target path.
  @override
  Object onInvoke(Map<String, dynamic> params) {
    provider.removeNode(targetPath);
    link.save();
    return {};
  }
}

main(List<String> args) async {
  link = new LinkProvider(args, "DartVM-", nodes: {
    "Add_VM": {
      r"$name": "Add VM",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "name",
          "type": "string",
          "placeholder": "MyVM"
        },
        {
          "name": "url",
          "type": "string",
          "default": "ws://localhost:8181/ws"
        }
      ],
      r"$columns": [
        {
          "name": "message",
          "type": "string"
        }
      ],
      r"$result": "values",
      r"$is": "addVM"
    }
  }, profiles: {
    "addVM": (String path) => new AddVMNode(path),
    "vm": (String path) => new VMNode(path),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider)
  }, autoInitialize: false);

  link.init();
  link.connect();
}

class AddVMNode extends SimpleNode {
  AddVMNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String name = params["name"];
    String url = params["url"];

    if (name == null || url == null || name.trim().isEmpty) {
      return {
        "message": "Name and URL should be provided"
      };
    }

    try {
      var socket = await WebSocket.connect(url);
      await socket.close();
    } catch (e) {
      return {
        "message": "ERROR: ${e}"
      };
    }

    link.addNode("/${name}", {
      r"$is": "vm",
      r"$url": url
    });

    link.save();

    return {
      "message": "Success!"
    };
  }
}

class VMNode extends SimpleNode {
  VMNode(String path) : super(path);

  @override
  onCreated() async {
    String url = configs[r"$url"];

    try {
      var socket = await WebSocket.connect(url);
      await socket.close();
    } catch (e) {
      link.addNode("${path}/Error", {
        r"$type": "string",
        "?value": e
      });
      return;
    }

    target = new WebSocketVMTarget(url);
    vm = new WebSocketVM(target);

    link.addNode("${path}/Remove", {
      r"$name": "Remove",
      r"$invokable": "write",
      r"$result": "values",
      r"$is": "remove"
    });

    vm = await vm.load();

    link.addNode("${path}/Version", {
      r"$type": "string",
      "?value": vm.version
    });

    link.addNode("${path}/PID", {
      r"$type": "number",
      "?value": vm.pid
    });

    link.addNode("${path}/Architecture_Bits", {
      r"$name": "Architecture Bits",
      r"$type": "number",
      "?value": vm.architectureBits
    });

    link.addNode("${path}/Start_Time", {
      r"$name": "Start Time",
      r"$type": "string",
      "?value": vm.startTime.toString()
    });

    link.addNode("${path}/Uptime", {
      r"$type": "number",
      "?value": vm.upTime.inMilliseconds,
      "@unit": "ms"
    });

    link.addNode("${path}/Isolates", {});

    var reloading = false;

    update() async {
      if (reloading) {
        return;
      }
      reloading = true;
      if (vm == null) {
        return;
      }

      if (vm.isDisconnected) {
        target = new WebSocketVMTarget(url);
        vm = new WebSocketVM(target);
      }

      await vm.reload();
      await vm.reloadIsolates();

      if (vm == null) {
        return;
      }

      link.updateValue("${path}/Uptime", vm.upTime.inMilliseconds);

      for (Isolate isolate in vm.isolates) {
        await isolate.reload();

        var p = "${path}/Isolates/${isolate.id.split("/").skip(1).join("_")}";
        SimpleNode node = link[p];

        if (node == null) {
          node = link.addNode(p, {
            r"$name": isolate.name,
            "Execute": {
              r"$type": "string",
              "?value": isolate.running ? isolate.topFrame.location.toString() : "Idle"
            },
            "Running": {
              r"$type": "bool",
              "?value": isolate.running
            },
            "New_Generation": {
              r"$name": "New Generation",
              "Collections": {
                r"$type": "number",
                "?value": isolate.newSpace.collections
              },
              "Average_Collection_Interval": {
                r"$type": "number",
                r"$name": "Average Collection Interval",
                "?value": isolate.newSpace.averageCollectionPeriodInMillis,
                "@unit": "ms"
              },
              "Used": {
                r"$type": "number",
                r"@unit": "bytes",
                "?value": isolate.newSpace.used
              },
              "Capacity": {
                r"$type": "number",
                "@unit": "bytes",
                "?value": isolate.newSpace.capacity
              },
              "External": {
                r"$type": "number",
                "@unit": "bytes",
                "?value": isolate.newSpace.external
              }
            },
            "Old_Generation": {
              r"$name": "Old Generation",
              "Collections": {
                r"$type": "number",
                "?value": isolate.oldSpace.collections
              },
              "Average_Collection_Interval": {
                r"$type": "number",
                r"$name": "Average Collection Interval",
                "?value": isolate.oldSpace.averageCollectionPeriodInMillis,
                "@unit": "ms"
              },
              "Used": {
                r"$type": "number",
                r"@unit": "bytes",
                "?value": isolate.oldSpace.used
              },
              "Capacity": {
                r"$type": "number",
                "@unit": "bytes",
                "?value": isolate.oldSpace.capacity
              },
              "External": {
                r"$type": "number",
                "@unit": "bytes",
                "?value": isolate.oldSpace.external
              }
            },
            "Start_Time": {
              r"$name": "Start Time",
              r"$type": "string",
              "?value": isolate.startTime.toString()
            },
            "Uptime": {
              r"$type": "number",
              "?value": isolate.upTime.inMilliseconds,
              "@unit": "ms"
            },
            "Idle": {
              r"$type": "bool",
              "?value": isolate.idle
            },
            "Paused": {
              r"$type": "bool",
              "?value": isolate.paused
            }
          });
        } else {
          var u = (n, v) {
            try {
              link.val("${node.path}/${n}", v);
            } catch (e) {}
          };
          u("Execute", isolate.running ? isolate.topFrame.location.toString() : "Idle");
          u("Running", isolate.running);
          for (var a in const ["New", "Old"]) {
            var space = a == "New" ? isolate.newSpace : isolate.oldSpace;
            u("${a}_Generation/Collections", space.collections);
            u("${a}_Generation/Average_Collection_Interval", space.averageCollectionPeriodInMillis);
            u("${a}_Generation/Capacity", space.capacity);
            u("${a}_Generation/Used", space.used);
            u("${a}_Generation/External", space.external);
          }
          u("Start_Time", isolate.startTime.toString());
          u("Uptime", isolate.upTime.inMilliseconds);
          u("Idle", isolate.idle);
          u("Paused", isolate.paused);
        }
      }

      link["${path}/Isolates"].children.keys.toList().forEach((x) {
        if (!vm.isolates.any((n) => n.id.split("/").skip(1).join("/") == x)) {
          link.removeNode("${path}/Isolates/${x}");
        }
      });
      reloading = false;
    }

    await update();

    timer = Scheduler.every(Interval.TWO_SECONDS, () async {
      try {
        await update();
      } catch (e) {
        print("Warning in ${path}: ${e}");
      }
    });
  }

  Timer timer;

  @override
  Map save() {
    String url = configs[r"$url"];
    return {
      r"$is": "vm",
      r"$url": url
    }..addAll(attributes);
  }

  @override
  onRemoving() {
    if (vm != null && !vm.isDisconnected) {
      vm.disconnect();
    }
    vm = null;
    target = null;

    if (timer != null) {
      timer.cancel();
      timer = null;
    }
  }

  WebSocketVMTarget target;
  WebSocketVM vm;
}

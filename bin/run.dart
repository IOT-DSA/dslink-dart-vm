import "package:dslink/dslink.dart";
import "dart:io";

import "package:vm_service/service_io.dart";
import "package:observe/observe.dart";

LinkProvider link;

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
    "vm": (String path) => new VMNode(path)
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
    vm = await vm.load();

    link.addNode("${path}/Version", {
      r"$type": "string",
      "?value": vm.version
    });

    link.addNode("${path}/Isolates", {});

    var reloading = false;

    update() async {
      if (reloading) {
        return;
      }
      reloading = true;

      for (Isolate isolate in vm.isolates) {
        await isolate.reload();
        var p = "${path}/Isolates/${isolate.id.split("/").skip(1).join("_")}";
        SimpleNode node = link[p];

        if (node == null) {
          node = link.addNode(p, {});
        }

        node.load({
          r"$name": isolate.name,
          "New_Generation": {
            r"$name": "New Generation",
            "Collections": {
              r"$type": "int",
              "?value": isolate.newSpace.collections
            },
            "Average_Collection_Interval": {
              r"$type": "number",
              r"$name": "Average Collection Interval",
              "?value": isolate.newSpace.averageCollectionPeriodInMillis
            },
            "Used": {
              r"$type": "int",
              r"@unit": "bytes",
              "?value": isolate.newSpace.used
            },
            "Capacity": {
              r"$type": "int",
              "@unit": "bytes",
              "?value": isolate.newSpace.capacity
            },
            "External": {
              r"$type": "int",
              "@unit": "bytes",
              "?value": isolate.newSpace.external
            }
          },
          "Old_Generation": {
            r"$name": "Old Generation",
            "Collections": {
              r"$type": "int",
              "?value": isolate.oldSpace.collections
            },
            "Average_Collection_Interval": {
              r"$type": "number",
              r"$name": "Average Collection Interval",
              "?value": isolate.oldSpace.averageCollectionPeriodInMillis
            },
            "Used": {
              r"$type": "int",
              r"@unit": "bytes",
              "?value": isolate.oldSpace.used
            },
            "Capacity": {
              r"$type": "int",
              "@unit": "bytes",
              "?value": isolate.oldSpace.capacity
            },
            "External": {
              r"$type": "int",
              "@unit": "bytes",
              "?value": isolate.oldSpace.external
            }
          },
          "Start_Time": {
            r"$name": "Start Time",
            r"$type": "string",
            "?value": isolate.startTime.toIso8601String()
          },
          "Uptime": {
            r"$type": "int",
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
      }

      link["${path}/Isolates"].children.keys.toList().forEach((x) {
        if (!vm.isolates.any((n) => n.id.split("/").skip(1).join("/") == x)) {
          link.removeNode("${path}/Isolates/${x}");
        }
      });
      reloading = false;
    }

    await update();

    vm.isolates.changes.listen((List<ChangeRecord> records) {
      update();
    });

    Scheduler.every(Interval.ONE_SECOND, () async {
      await update();
    });
  }

  @override
  Map save() {
    String url = configs[r"$url"];
    return {
      r"$is": "vm",
      r"$url": url
    }..addAll(attributes);
  }

  WebSocketVMTarget target;
  WebSocketVM vm;
}


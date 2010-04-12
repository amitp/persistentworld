// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

// Next steps:
// * Json-evaluate the messages
  
package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;
  import com.adobe.serialization.json.*;
  
  public class client extends Sprite {
    public var socket:Socket = new Socket();
    public var clientId:String = String(1000 + Math.floor(Math.random() * 9000));
    public var pingTimer:Timer = new Timer(1000/10, 0);

    public static var serverAddress:String = null;
    public static var serverPort:int = 8001;
    
    public function client() {
      stage.frameRate = 30;
      
      addChild(new Debug(this));

      var buffer:ByteArray = new ByteArray();

      stage.addEventListener(Event.ACTIVATE, onActivate);
      stage.addEventListener(Event.DEACTIVATE, onDeactivate);
      
      socket.addEventListener(Event.CONNECT, function (e:Event):void {
          Debug.trace("CONNECT");
          // socket.writeByte(0);
        });
      socket.addEventListener(Event.CLOSE, function (e:Event):void {
          Debug.trace("CLOSE");
        });
      socket.addEventListener(IOErrorEvent.IO_ERROR,
                              function (e:IOErrorEvent):void {
                                Debug.trace("ERROR", e);
                              });
      socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR,
                              function (e:SecurityErrorEvent):void {
                                Debug.trace("SECURITY_ERROR", e);
                              });
      socket.addEventListener(ProgressEvent.SOCKET_DATA,
                              function (e:ProgressEvent):void {
                                var i:int = buffer.length;

                                socket.readBytes(buffer, buffer.length, socket.bytesAvailable);
                                for (; i <= buffer.length; i++) {
                                  if (buffer[i] == 0) {
                                    var message:String = buffer.readUTFBytes(i - buffer.position);
                                    if (buffer.readByte() != 0) throw(new Error("Expecting NUL byte"));
                                    handleMessage(message);
                                  }
                                }
                                if (buffer.position == buffer.length) {
                                  // Reading from the ByteArray
                                  // doesn't remove the data, so we
                                  // need to do it ourselves when it's
                                  // safe to do (e.g. nothing is
                                  // buffered).
                                  buffer.clear();
                                }
                              });

      Debug.trace("Connecting");
      socket.connect(serverAddress, serverPort);
      
      pingTimer.addEventListener(TimerEvent.TIMER, onTimer);
    }

    public function onActivate(e:Event):void {
      Debug.trace("ACTIVATE");
      // NOTE: the Debug panel is eating up the mouse events, so we grab from stage instead
      stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
      pingTimer.start();
    }

    public function onDeactivate(e:Event):void {
      Debug.trace("DEACTIVATE");
      stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
      pingTimer.stop();
    }

    public function onMouseMove(e:MouseEvent):void {
      sendMessage({type: 'mouse_move', id: clientId, x: e.localX, y: e.localY});
    }

    public function sendMessage(message:Object):void {
      socket.writeUTFBytes(JSON.encode(message));
      socket.writeByte(0);
    }
    
    public function handleMessage(msg:String):void {
      // Debug.trace("HANDLE MESSAGE", msg);
      var message:Object = JSON.decode(msg);
      if (message.type == 'all_positions') {
        Debug.trace('ping time', getTimer() - message.timestamp, 'ms');
        graphics.clear();
        for (var id:String in message.positions) {
            var position:Object = message.positions[id];
            graphics.beginFill(id == clientId? 0x555599 : 0x995555);
            graphics.drawRect(position.x - 10, position.y - 10, 20, 20);
            graphics.endFill();
          }
      }
    }

    public function onTimer(e:TimerEvent):void {
      sendMessage({type: 'ping', timestamp: getTimer()});
    }
  }
}


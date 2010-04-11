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
    
    public function client() {
      stage.frameRate = 5;
      
      graphics.beginFill(0x00ff00);
      graphics.drawRect(0, 0, 200, 200);
      graphics.endFill();
      
      addChild(new Debug(this));

      var buffer:ByteArray = new ByteArray();
      
      socket.addEventListener(Event.CONNECT, function (e:Event):void {
          Debug.trace("CONNECT");
          socket.writeByte(0);
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
                                Debug.trace("SOCKET DATA", socket.bytesAvailable, "buffer:", buffer.length);
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
                                
                                socket.writeUTFBytes(JSON.encode({foo: 5}));
                                socket.writeByte(0);
                                socket.writeUTFBytes(JSON.encode({bar: 3}));
                                socket.writeByte(0);
                              });

      Debug.trace("Connecting");
      socket.connect("localhost", 8001);
      
      /*
      var timer:Timer = new Timer(1000/60, 0);
      timer.addEventListener(TimerEvent.TIMER, jitter);
      timer.start();
      */
    }

    public function handleMessage(msg:String):void {
      Debug.trace("HANDLE MESSAGE", msg);
    }
    
    public function jitter(e:TimerEvent):void {
    }
  }
}


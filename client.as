// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;
  
  public class client extends Sprite {
    public var socket:Socket = new Socket();
    
    public function client() {
      stage.frameRate = 60;
      
      graphics.beginFill(0x00ff00);
      graphics.drawRect(0, 0, 200, 200);
      graphics.endFill();
      
      addChild(new Debug(this));

      
      socket.addEventListener(Event.CONNECT, function (e:Event):void {
          Debug.trace("CONNECT");
          socket.writeUTFBytes("test");
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
                                // Debug.trace("SOCKET DATA", e, socket.readUTFBytes(socket.bytesAvailable));
                                socket.writeUTFBytes("testing round trip speed");
                              });

      Debug.trace("Connecting");
      socket.connect("localhost", 8001);
      
      /*
      var timer:Timer = new Timer(1000/60, 0);
      timer.addEventListener(TimerEvent.TIMER, jitter);
      timer.start();
      */
    }

    public function jitter(e:TimerEvent):void {
    }
  }
}


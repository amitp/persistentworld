// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.text.*;
  
  public class gameclient extends Sprite {
    static public var BITMAPSCALE:Number = 20.0/400;
    public var mapBitmap:BitmapData = new BitmapData(20, 20);
    public var colorMap:Array = [];
    public var client:Client = new Client();
    public var pingTime:TextField = new TextField();
    public var bufferView:TextField = new TextField();
    public var location:Array = [1000, 1000];
    public var moving:Boolean = false;
    
    public function gameclient() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';
      stage.frameRate = 30;
      
      var b:Bitmap = new Bitmap(mapBitmap);
      b.scaleX = 1.0/BITMAPSCALE;
      b.scaleY = 1.0/BITMAPSCALE;
      b.smoothing = false;
      addChild(b);

      pingTime.x = 50;
      pingTime.y = 440;
      addChild(pingTime);
      bufferView.width = 400;
      bufferView.x = 0;
      bufferView.y = 410;
      addChild(bufferView);
      
      addChild(new Debug(this)).x = 410;

      stage.addEventListener(Event.ACTIVATE, function (e:Event):void {
          Debug.trace("ACTIVATE -- got focus, now use arrow keys");
          client.activate();
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          Debug.trace("DEACTIVATE -- lost focus, click to activate");
          client.deactivate();
        });

      stage.addEventListener(KeyboardEvent.KEY_DOWN, function (e:KeyboardEvent):void {
          e.updateAfterEvent();
          Debug.trace("KEY DOWN", e.keyCode);

          var step:int = 5;
          var newLoc:Array = [location[0], location[1]];
          if (e.keyCode == 39 /* RIGHT */) { newLoc[0] += step; }
          else if (e.keyCode == 37 /* LEFT */) { newLoc[0] -= step; }
          else if (e.keyCode == 38 /* UP */) { newLoc[1] -= step; }
          else if (e.keyCode == 40 /* DOWN */) { newLoc[1] += step; }

          if (newLoc[0] != location[0] || newLoc[1] != location[1]) {
            if (!moving) {
              Debug.trace("MOVE REQ", location, "->", newLoc);
              moving = true;
              client.sendMessage({
                  type: 'move',
                    timestamp: getTimer(),
                    from: location,
                    to: newLoc
                    });
            } else {
              Debug.trace("ALREADY MOVING");
            }
          }
        });
        
      client.onMessageCallback = handleMessage;
      client.onSocketReceive = function():void {
        bufferView.text = "RECV BUFFER:" + client.buffer.position + "/" + client.buffer.length;
        if (client.buffer.length >= 8) {
          var prevPosition:int = client.buffer.position;
          var sizeBuffer:ByteArray = new ByteArray();
          client.buffer.readBytes(sizeBuffer, 0, 4);
          var len1:int = Client.binaryToInt32LittleEndian(sizeBuffer);
          client.buffer.readBytes(sizeBuffer, 0, 4);
          var len2:int = Client.binaryToInt32LittleEndian(sizeBuffer);
          bufferView.text = "RECV PARTIAL:" + client.buffer.position + "/" + client.buffer.length + " " + len1 + ".." + len2 + "? " + client.buffer.bytesAvailable;
          client.buffer.position = prevPosition;
        }
      };
      
      client.connect();
    }

    public function handleMessage(message:Object, binaryPayload:ByteArray):void {
      if (message.type == 'move_ok') {
        moving = false;
        Debug.trace("MOVE_OK", message.type, message.loc);
        location = message.loc;
        
        var radius:int = 10;
        client.sendMessage({
            type: 'map_tiles',
              timestamp: getTimer(),
              left: location[0] - radius,
              right: location[0] + radius,
              top: location[1] - radius,
              bottom: location[1] + radius});
      } else if (message.type == 'pong') {
        pingTime.text = "ping time: " + (getTimer() - message.timestamp) + "ms";
      } else if (message.type == 'map_tiles') {
        if (colorMap.length == 0) buildColorMap();
        var i:int = 0;
        mapBitmap.lock();
        for (var x:int = message.left; x < message.right; x++) {
          for (var y:int = message.top; y < message.bottom; y++) {
            var tileId:int = binaryPayload[i++];
            mapBitmap.setPixel(x - location[0] + mapBitmap.width/2,
                               y - location[1] + mapBitmap.height/2,
                               colorMap[tileId]);
          }
        }
        mapBitmap.unlock();
      }
    }

    // Initialize the colorMap array to map tileId into color
    public function buildColorMap():void {
      // Interpolate between A and B, frac=1.0 means B
      function interpolateColor(color1:int, color2:int, frac:Number):int {
        var r1:int = (color1 >> 16) & 0xff;
        var g1:int = (color1 >> 8) & 0xff;
        var b1:int = color1 & 0xff;
        var r2:int = (color2 >> 16) & 0xff;
        var g2:int = (color2 >> 8) & 0xff;
        var b2:int = color2 & 0xff;
        var r3:int = int(r1 * (1.0-frac) + r2 * frac);
        var g3:int = int(g1 * (1.0-frac) + g2 * frac);
        var b3:int = int(b1 * (1.0-frac) + b2 * frac);
        return (r3 << 16) | (g3 << 8) | b3;
      }
      
      colorMap[0] = 0x3d526d;
      colorMap[1] = 0x374b63;
      for (var altitude:int = 0; altitude < 10; altitude++) {
        var dry:int = interpolateColor(0xb19772, 0xcfb78b, altitude/9.0);
        var wet:int = interpolateColor(0x1d8e39, 0x97cb1b, altitude/9.0);
        for (var moisture:int = 0; moisture < 25; moisture++) {
          var index:int = 2 + altitude + 10*moisture;
          colorMap[index] = interpolateColor(dry, wet, moisture/24.0);
        }
      }
    }
  }
}


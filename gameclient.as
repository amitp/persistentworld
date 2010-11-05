// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  
  public class gameclient extends Sprite {
    static public var BITMAPSCALE:Number = 6.0;
    public var mapBitmap:BitmapData = new BitmapData(2048, 2048);
    public var colorMap:Array = [];
    public var client:Client = new Client();
    
    public function gameclient() {
      stage.frameRate = 30;
      
      var b:Bitmap = new Bitmap(mapBitmap);
      b.scaleX = 1.0/BITMAPSCALE;
      b.scaleY = 1.0/BITMAPSCALE;
      b.smoothing = true;
      addChild(b);
      
      addChild(new Debug(this)).x = 350;

      stage.addEventListener(Event.ACTIVATE, function (e:Event):void {
          Debug.trace("ACTIVATE -- got focus, now move the mouse around");
          stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          Debug.trace("DEACTIVATE -- lost focus, click to activate");
          stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        });
      
      client.onMessageCallback = handleMessage;
      client.connect();
    }

    public function onMouseMove(e:MouseEvent):void {
      // sendMessage({type: 'mouse_move', id: clientId, x: e.localX, y: e.localY});
      var radius:int = 20 * BITMAPSCALE;
      client.sendMessage({type: 'map_tiles', timestamp: getTimer(), left: e.localX*BITMAPSCALE-radius, right: e.localX*BITMAPSCALE+radius, top: e.localY*BITMAPSCALE-radius, bottom: e.localY*BITMAPSCALE+radius});
    }

    public function handleMessage(message:Object, binaryPayload:ByteArray):void {
      // Debug.trace("HANDLE MESSAGE", msg);
      if (message.type == 'all_positions') {
        /*
        Debug.trace('ping time', getTimer() - message.timestamp, 'ms');
        graphics.clear();
        for (var id:String in message.positions) {
            var position:Object = message.positions[id];
            graphics.beginFill(id == clientId? 0x555599 : 0x995555);
            graphics.drawRect(position.x - 10, position.y - 10, 20, 20);
            graphics.endFill();
          }
        */
      } else if (message.type == 'map_tiles') {
        Debug.trace('ping time: ', getTimer() - message.timestamp, 'ms');
        if (colorMap.length == 0) buildColorMap();
        var i:int = 0;
        mapBitmap.lock();
        for (var x:int = message.left; x < message.right; x++) {
          for (var y:int = message.top; y < message.bottom; y++) {
            var tileId:int = binaryPayload[i++];
            mapBitmap.setPixel(x, y, colorMap[tileId]);
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
        for (var moisture:int = 0; moisture < 10; moisture++) {
          var index:int = 100 + altitude + 10*moisture;
          colorMap[index] = interpolateColor(dry, wet, moisture/9.0);
        }
      }
    }
  }
}


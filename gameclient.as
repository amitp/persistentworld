// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.text.*;
  
  public class gameclient extends Sprite {
    static public var TILES_ON_SCREEN:int = 25;
    static public var TILE_PADDING:int = 3;
    static public var WALK_TIME:Number = 150;
    static public var WALK_STEP:int = 2;
    
    public var mapBitmapData:BitmapData = new BitmapData(TILES_ON_SCREEN + 2*TILE_PADDING,
                                                         TILES_ON_SCREEN + 2*TILE_PADDING,
                                                         false, 0x00ccddcc);
    public var mapBitmap:Bitmap;

    public var colorMap:Array = [];
    public var client:Client = new Client();
    public var pingTime:TextField = new TextField();
    public var location:Array = [945, 1220];
    public var moving:Boolean = false;
    public var _keyQueue:KeyboardEvent = null;  // next key that we haven't processed yet
    
    public var animationState:Object = null;
    
    public function gameclient() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';
      stage.frameRate = 30;

      var mapMask:Shape = new Shape();
      mapMask.graphics.beginFill(0x000000);
      mapMask.graphics.drawRect(0, 0, 400, 400);
      mapMask.graphics.endFill();
      var mapParent:Sprite = new Sprite();
      mapParent.mask = mapMask;
      addChild(mapParent);
      addChild(mapMask);
      
      mapBitmap = new Bitmap(mapBitmapData);
      mapBitmap.scaleX = mapBitmap.scaleY = 400.0/TILES_ON_SCREEN;
      mapBitmap.smoothing = false;

      mapMask.x = mapParent.x = 10;
      mapMask.y = mapParent.y = 10;
      mapParent.addChild(mapBitmap);
      
      pingTime.x = 50;
      pingTime.y = 410;
      addChild(pingTime);
      
      addChild(new Debug(this)).x = 410;

      addEventListener(Event.ENTER_FRAME, onEnterFrame);
      
      stage.addEventListener(Event.ACTIVATE, function (e:Event):void {
          Debug.trace("ACTIVATE -- got focus, now use arrow keys");
          client.activate();
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          Debug.trace("DEACTIVATE -- lost focus, click to activate");
          client.deactivate();
        });

      stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
      client.onMessageCallback = handleMessage;
      
      client.connect();
      client.sendMessage({
          type: 'move',
            from: location,
            to: location,
            left: location[0] - TILES_ON_SCREEN,
            right: location[0] + TILES_ON_SCREEN,
            top: location[1] - TILES_ON_SCREEN,
            bottom: location[1] + TILES_ON_SCREEN
            });
    }

    
    public function onEnterFrame(e:Event):void {
      var time:Number = getTimer();
      var f:Number, aX:Number, aY:Number;

      if (animationState) {
        if (time < animationState.endTime) {
          f = (time - animationState.beginTime) / (animationState.endTime - animationState.beginTime);
        } else {
          f = 1.0;
        }
        aX = (1-f) * animationState.beginLocation[0] + f * animationState.endLocation[0];
        aY = (1-f) * animationState.beginLocation[1] + f * animationState.endLocation[1];

        if (time >= animationState.endTime) {
          if (animationState.endLocation[0] == location[0] && animationState.endLocation[1] == location[1]) {
            animationState = null;
          } else {
            Debug.trace("delaying animation removal ", animationState.endLocation, location);
          }
        }
      } else {
        aX = location[0];
        aY = location[1];
        if (_keyQueue) onKeyDown(_keyQueue, true);
      }
      if (animationState != null || e == null) {
        mapBitmap.x = mapBitmap.scaleX * (location[0] - aX - TILE_PADDING);
        mapBitmap.y = mapBitmap.scaleY * (location[1] - aY - TILE_PADDING);
      }
    }


    public function onKeyDown(e:KeyboardEvent, replay:Boolean = false):void {
      var now:Number;
      if (!replay) Debug.trace("KEY DOWN", e.keyCode);

      var newLoc:Array = [location[0], location[1]];
      if (e.keyCode == 39 /* RIGHT */) { newLoc[0] += WALK_STEP; }
      else if (e.keyCode == 37 /* LEFT */) { newLoc[0] -= WALK_STEP; }
      else if (e.keyCode == 38 /* UP */) { newLoc[1] -= WALK_STEP; }
      else if (e.keyCode == 40 /* DOWN */) { newLoc[1] += WALK_STEP; }
          
      if (newLoc[0] != location[0] || newLoc[1] != location[1]) {
        if (replay) _keyQueue = null;
        if (!moving && animationState == null) {
          e.updateAfterEvent();
          Debug.trace("MOVE REQ", location, "->", newLoc);
          moving = true;
          var radius:int = TILE_PADDING + TILES_ON_SCREEN;;
          client.sendMessage({
              type: 'move',
                from: location,
                to: newLoc,
                left: newLoc[0] - radius,
                right: newLoc[0] + radius,
                top: newLoc[1] - radius,
                bottom: newLoc[1] + radius
                });
          now = getTimer();
          animationState = {
            beginLocation: location,
            endLocation: newLoc,
            beginTime: now,
            endTime: now + WALK_TIME
          };
        } else {
          if (_keyQueue == null) {
            _keyQueue = e;
          }
        }
      }
    }

    
    public function handleMessage(message:Object, binaryPayload:ByteArray):void {
      if (message.type == 'move_ok') {
        moving = false;
        Debug.trace("MOVE_OK", message.type, message.loc);
        location = message.loc;

        // For now, the move_ok message gets the tile data
        // piggybacked. This is because we assume the bitmap's center
        // is the current location, so we have to update both the
        // location and the bitmap at the same time. In the future
        // we'll cache parts of the map and will request only areas
        // that need it.
        if (colorMap.length == 0) buildColorMap();
        var i:int = 0;
        mapBitmapData.lock();
        for (var x:int = message.left; x < message.right; x++) {
          for (var y:int = message.top; y < message.bottom; y++) {
            var tileId:int = binaryPayload[i++];
            mapBitmapData.setPixel(x - location[0] + mapBitmapData.width/2,
                                   y - location[1] + mapBitmapData.height/2,
                                   colorMap[tileId]);
          }
        }
        mapBitmapData.setPixel(0, 0, 0);
        mapBitmapData.setPixel(mapBitmapData.width-1, 0, 0);
        mapBitmapData.setPixel(mapBitmapData.width-1, mapBitmapData.height-1, 0);
        mapBitmapData.unlock();
        onEnterFrame(null);  // HACK: reposition the bitmap properly
        if (_keyQueue) onKeyDown(_keyQueue, true);
      } else if (message.type == 'pong') {
        pingTime.text = "ping time: " + (getTimer() - message.timestamp) + "ms";
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
      
      colorMap[0] = 0x225588;
      colorMap[1] = 0x553322;
      for (var altitude:int = 0; altitude < 10; altitude++) {
        var dry:int = interpolateColor(0xb19772, 0xcfb78b, altitude/9.0);
        var wet:int = interpolateColor(0x1d8e39, 0x97cb1b, altitude/9.0);
        for (var moisture:int = 0; moisture < 10; moisture++) {
          var index:int = 2 + altitude + 10*moisture;
          colorMap[index] = interpolateColor(dry, wet, moisture/9.0);
        }
      }
    }
  }
}


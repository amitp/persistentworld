// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import amitp.*;
  import assets.*;
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.text.*;
  import flash.geom.*;
  import com.gskinner.motion.GTween;
  
  public class gameclient extends Sprite {
    static public var TILES_ON_SCREEN:int = 13;
    static public var TILE_PADDING:int = 3;
    static public var WALK_TIME:Number = 150;
    static public var WALK_STEP:int = 1;
    
    public var mapBitmapData:BitmapData = new BitmapData(TILES_ON_SCREEN + 2*TILE_PADDING,
                                                         TILES_ON_SCREEN + 2*TILE_PADDING,
                                                         false, 0x00ccddcc);
    public var mapBitmap:Bitmap;
    public var mapParent:Sprite = new Sprite();

    public var camera:Object = { x: 0, y: 0, z: 0 };

    public var clickToFocusMessage:Sprite = new Sprite();
    
    public var spritesheet:Spritesheet = new oddball_char();
    public var spriteId:int = int(Math.random()*255);
    public var playerName:String = "guest";
    public var playerStyle:Object = spritesheet.makeStyle();
    public var playerBitmap:Bitmap = new Bitmap(new BitmapData(2*2 + 8*3, 2*2 + 8*3, true, 0x00000000));
    public var location:Array = [945, 1220];
    public var moving:Boolean = false;
    public var _keyQueue:KeyboardEvent = null;  // next key that we haven't processed yet
    
    public var animationState:Object = null;

    public var otherPlayers:Object = {};  // {clientId: {sprite_id: bitmap: loc:}}
    
    public var colorMap:Array = [];
    public var client:Client = new Client();
    public var pingTime:TextField = new TextField();
    public var inputField:TextField = new TextField();
    public var outputMessages:TextField = new TextField();
    
    public function gameclient() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';
      stage.frameRate = 30;

      addChild(new Debug(this)).x = 410;

      clickToFocusMessage.x = 100;
      clickToFocusMessage.y = 300;
      clickToFocusMessage.graphics.beginFill(0x000000, 0.7);
      clickToFocusMessage.graphics.drawRoundRect(0, 0, 200, 90, 35, 35);
      clickToFocusMessage.graphics.endFill();
      clickToFocusMessage.addChild(Text.createTextLine("Click to activate", 50, 50, {fontSize:14, color: 0xffffff}));
      addChild(clickToFocusMessage);

      var tween:GTween = new GTween(clickToFocusMessage, 1, {},
                                    {onComplete: function():void { clickToFocusMessage.visible =
                                                                   (clickToFocusMessage.alpha != 0.0); }});
      stage.addEventListener(Event.ACTIVATE, function (e:Event):void {
          client.activate();
          tween.duration = 0.15;
          tween.setValue('alpha', 0.0);
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          client.deactivate();
          clickToFocusMessage.visible = true;
          tween.duration = 1.5;
          tween.setValue('alpha', 1.0);
        });
      
      client.onMessageCallback = handleMessage;
      client.connect();
      setupIntroUi();
    }


    public function setupIntroUi():void {
      var preview:Sprite = new Sprite();
      var title:DisplayObject = Text.createTextLine("Welcome to Nakai's secret volcano island.", 50, 50, {fontSize: 18});
      var label:DisplayObject = Text.createTextLine("Enter your name:", 150, 180, {fontSize: 16});
      var playerNameEntry:TextField = new TextField();

      function introUiCleanup():void {
        stage.focus = null;
        playerName = playerNameEntry.text;
        // TODO: for proper cleanup, need to remove event listeners
        preview.removeChild(previewBitmap);
        removeChild(playerNameEntry);
        removeChild(preview);
        removeChild(label);
        removeChild(title);
        setupGameUi();
      }

      var style:Object = spritesheet.makeStyle();
      style.scale = 13;
      style.padding = 6;
      style.bevelWidth = 2;
      style.bevelBlur = 4;
      style.outlineAlpha = 1.0;
      style.outlineBlur = 5;
      var previewBitmap:Bitmap = new Bitmap(new BitmapData(2*style.padding + 8*style.scale, 2*style.padding + 8*style.scale, true, 0x000000));
      style.saturation = 0.9;
      spritesheet.drawToBitmap(spriteId, previewBitmap.bitmapData, style);
      previewBitmap.x = 30;
      previewBitmap.y = 130;
      preview.addChild(previewBitmap);

      preview.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void {
          spriteId = int(Math.random()*255);
          spritesheet.drawToBitmap(spriteId, previewBitmap.bitmapData, style);
          e.updateAfterEvent();
        });
      addChild(preview);
      
      playerNameEntry.x = 150;
      playerNameEntry.y = 200-13;
      playerNameEntry.width = 200;
      playerNameEntry.height = 15;
      playerNameEntry.border = true;
      playerNameEntry.borderColor = 0x009966;
      playerNameEntry.backgroundColor = 0x99ffdd;
      playerNameEntry.type = TextFieldType.INPUT;
      playerNameEntry.maxChars = 8;
      playerNameEntry.restrict = "A-Za-z";
      playerNameEntry.addEventListener(FocusEvent.FOCUS_IN, function (e:FocusEvent):void {
          playerNameEntry.background = true;
        });
      playerNameEntry.addEventListener(FocusEvent.FOCUS_OUT, function (e:FocusEvent):void {
          playerNameEntry.background = false;
        });
      playerNameEntry.addEventListener(KeyboardEvent.KEY_UP, function (e:KeyboardEvent):void {
          if (e.keyCode == 13 && playerNameEntry.text.length == 0) playerNameEntry.text = "Guest"; // HACK: for quicker testing

          
          if (e.keyCode == 13 /* Enter */ && playerNameEntry.text.length > 0) introUiCleanup();
        });
            
      addChild(playerNameEntry);
      addChild(label);
      addChild(title);
      stage.focus = playerNameEntry;
    }

    
    public function setupGameUi():void {
      var mapMask:Shape = new Shape();
      mapMask.graphics.beginFill(0x000000);
      mapMask.graphics.drawRect(0, 0, 400, 400);
      mapMask.graphics.endFill();
      mapParent.mask = mapMask;
      addChild(mapParent);
      addChild(mapMask);

      mapBitmap = new Bitmap(mapBitmapData);
      mapBitmap.scaleX = mapBitmap.scaleY = 400.0/TILES_ON_SCREEN;
      mapBitmap.smoothing = false;

      mapMask.x = mapParent.x = 10;
      mapMask.y = mapParent.y = 10;
      mapParent.addChild(mapBitmap);

      playerStyle.saturation = 0.9;
      spritesheet.drawToBitmap(spriteId, playerBitmap.bitmapData, playerStyle);
      playerBitmap.x = (400.0-playerBitmap.width)/2;
      playerBitmap.y = (400.0-playerBitmap.height)/2;
      mapParent.addChild(playerBitmap);
      
      pingTime.x = 10;
      pingTime.y = 10;
      addChild(pingTime);

      inputField.x = 10;
      inputField.y = 410;
      inputField.width = 398;
      inputField.height = 15;
      inputField.border = true;
      inputField.borderColor = 0x000099;
      inputField.backgroundColor = 0x99ffdd;
      inputField.type = TextFieldType.INPUT;
      addChild(inputField);

      inputField.addEventListener(FocusEvent.FOCUS_IN, function (e:FocusEvent):void {
          inputField.background = true;
        });
      inputField.addEventListener(FocusEvent.FOCUS_OUT, function (e:FocusEvent):void {
          inputField.background = false;
        });

      outputMessages.x = 10;
      outputMessages.y = 430;
      outputMessages.width = 398;
      outputMessages.height = 100;
      outputMessages.border = true;
      outputMessages.borderColor = 0x666600;
      outputMessages.text = "Arrows to move. Enter to chat.";
      addChild(outputMessages);

      // Move this to the top
      removeChild(clickToFocusMessage);
      addChild(clickToFocusMessage);
      
      addEventListener(Event.ENTER_FRAME, onEnterFrame);
      
      stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
      client.sendMessage({
          type: 'identify',
            name: playerName,
            sprite_id: spriteId
            });
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
      var f:Number;

      if (animationState) {
        if (time < animationState.endTime) {
          f = (time - animationState.beginTime) / (animationState.endTime - animationState.beginTime);
        } else {
          f = 1.0;
        }
        camera.x = (1-f) * animationState.beginLocation[0] + f * animationState.endLocation[0];
        camera.y = (1-f) * animationState.beginLocation[1] + f * animationState.endLocation[1];

        if (time >= animationState.endTime) {
          if (animationState.endLocation[0] == location[0] && animationState.endLocation[1] == location[1]) {
            animationState = null;
            e = null;  // hack to make sure we still set x,y
          } else {
            Debug.trace("delaying animation removal ", animationState.endLocation, location);
          }
        }
      } else {
        camera.x = location[0];
        camera.y = location[1];
        if (_keyQueue) onKeyDown(_keyQueue, true);
      }
      if (animationState != null || e == null) {
        mapBitmap.x = mapBitmap.scaleX * (location[0] - camera.x - TILE_PADDING);
        mapBitmap.y = mapBitmap.scaleY * (location[1] - camera.y - TILE_PADDING);
        moveOtherPlayers();
      }
    }


    // Make sure all other player sprites are in the right place relative to the map
    public function moveOtherPlayers():void {
      for each (var other:Object in otherPlayers) {
          other.bitmap.x = playerBitmap.x + mapBitmap.scaleX * (other.loc[0] - camera.x);
          other.bitmap.y = playerBitmap.y + mapBitmap.scaleY * (other.loc[1] - camera.y);
        }
    }

    
    public function onKeyDown(e:KeyboardEvent, replay:Boolean = false):void {
      var now:Number;
      if (!replay) Debug.trace("KEY DOWN", e.keyCode, stage.focus == null? "/stage":"/input");

      var newLoc:Array = [location[0], location[1]];
      if (e.keyCode == 13 /* Enter */) {
        if (stage.focus == inputField) {
          // End text entry by sending to server
          client.sendMessage({
              type: 'message',
                message: inputField.text
                });
          inputField.text = "";
          stage.focus = null;
        } else {
          // Start text entry
          stage.focus = inputField;
        }
      }

      // While entering text, other keys don't apply
      if (stage.focus == inputField) return;
      
      if (e.keyCode == 39 /* RIGHT */) { newLoc[0] += WALK_STEP; }
      else if (e.keyCode == 37 /* LEFT */) { newLoc[0] -= WALK_STEP; }
      else if (e.keyCode == 38 /* UP */) { newLoc[1] -= WALK_STEP; }
      else if (e.keyCode == 40 /* DOWN */) { newLoc[1] += WALK_STEP; }
          
      if (newLoc[0] != location[0] || newLoc[1] != location[1]) {
        if (replay) _keyQueue = null;
        if (!moving && animationState == null) {
          e.updateAfterEvent();
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
      } else if (message.type == 'player_positions') {
        for each (var other:Object in message.positions) {
            // Make sure we have an entry in otherPlayers
            if (otherPlayers[other.id] == null) {
              otherPlayers[other.id] = {
                sprite_id: -1,
                bitmap: new Bitmap(new BitmapData(playerBitmap.width, playerBitmap.height, true, 0x00000000))
              };
              mapParent.addChild(otherPlayers[other.id].bitmap);
            }
            // TODO: remove entries for players not sent to us
            
            // Make sure we've drawn the bitmap
            if  (otherPlayers[other.id].sprite_id != other.sprite_id) {
              spritesheet.drawToBitmap(other.sprite_id, otherPlayers[other.id].bitmap.bitmapData, playerStyle);
            }
            // Copy the updated data into our record
            otherPlayers[other.id].sprite_id = other.sprite_id;
            otherPlayers[other.id].loc = other.loc;
          }
        moveOtherPlayers();
      } else if (message.type == 'messages') {
        outputMessages.text = outputMessages.text + "\n" + message.messages.join("\n");
        outputMessages.scrollV = outputMessages.maxScrollV;
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


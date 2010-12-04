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
  import flash.net.SharedObject;
  import com.gskinner.motion.GTween;
  import com.gskinner.motion.easing.*;
  
  public class gameclient extends Sprite {
    static public var TILES_ON_SCREEN:int = 13;
    static public var TILE_PADDING:int = 3;
    static public var WALK_TIME:Number = 200;
    static public var WALK_STEP:int = 1;
    
    // The map area contains all the tile blocks and other players,
    // positioned in absolute coordinate space. Moving the camera
    // means moving and zooming the map area within the map
    // parent. You can think of the map parent as being a "window" on
    // top of the map area. The map area is divided into three layers:
    // terrainLayer, itemLayer, characterLayer.
    static public var mapScale:Number = 3.0 * 8;
    public var terrainLayer:Sprite = new Sprite();
    public var itemLayer:Sprite = new Sprite();
    public var characterLayer:Sprite = new Sprite();
    public var mapArea:Sprite = new Sprite();
    public var mapSprite:Sprite = new Sprite();
    public var mapParent:Sprite = new Sprite();

    public var camera:Object = { x: 0, y: 0, z: 0 };
    public var cameraZoomTween:GTween = new GTween(this, 0.3, {}, {}, Linear.easeNone);
    public function get cameraZ():Number { return camera.z; }
    public function set cameraZ(z:Number):void {
      camera.z = z;
      var zoom:Number = 10.0 / (10+camera.z);
      playerSprite.scaleX = playerSprite.scaleY = Math.max(1.0, 1.0/(zoom*zoom));
      mapSprite.scaleX = mapSprite.scaleY = zoom;
    }

    public var clickToFocusMessage:Sprite = new Sprite();
    
    public var char_spritesheet:Spritesheet = new oddball_char();
    public var tile_spritesheet:Spritesheet = new oddball_tile();
    public var spriteId:int = int(Math.random()*272);  // 273 sprites in oddball_char
    public var playerName:String = "guest";
    public var playerStyle:Object = char_spritesheet.makeStyle();
    public var playerIconStyle:Object = char_spritesheet.makeStyle();
    public var playerBitmap:Bitmap = new Bitmap(new BitmapData(2*2 + 8*3, 2*2 + 8*3, true, 0x00000000));
    public var playerSprite:Sprite = new Sprite();

    // Only present during the login, and null at other times:
    public var playerNameEntry:TextField = null;
    
    public var location:Array = [945, 1220];
    public var moving:Boolean = false;
    public var _keyQueue:KeyboardEvent = null;  // next key that we haven't processed yet
    
    public var animationState:Object = null;

    // Map objects:
    public var items:Object = {};  // {loc.toString(): {sprite: obj:}}
    public var creatures:Object = {};  // {obj id: clientId: {sprite: bitmap: obj:}}
    public var myCreatureId:String = "";

    public var colorMap:Array = [];
    public var client:Client = new Client();
    public var pingTime:TextField = new TextField();
    public var inputField:TextField = new TextField();
    public var outputMessages:OutputMessageBox = new OutputMessageBox(400, 200);
    
    public function gameclient() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';
      stage.frameRate = 60;

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
          if (playerNameEntry != null) stage.focus = playerNameEntry;
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          client.deactivate();
          clickToFocusMessage.visible = true;
          tween.duration = 1.5;
          tween.setValue('alpha', 1.0);
        });

      var timer:Timer = new Timer(50, 1);
      timer.addEventListener(TimerEvent.TIMER,
                             function (e:TimerEvent):void {
                               client.onMessageCallback = handleMessage;
                               client.connect();
                             });
      timer.start();
      
      var debugMode:Boolean = false;
      CONFIG::debugging {
        debugMode = true;
      }

      if (debugMode) {
        setupGameUi();
      } else {
        setupIntroUi();
      }
    }


    public function setupIntroUi():void {
      var preview:Sprite = new Sprite();
      var title:DisplayObject = Text.createTextLine("Welcome to Nakai's secret volcano island.", 50, 50, {fontSize: 18});
      var label:DisplayObject = Text.createTextLine("Enter your name:", 150, 180, {fontSize: 16});

      playerNameEntry = new TextField();
      
      // TODO: validate the values we get from the cookie
      var so:SharedObject = SharedObject.getLocal("username");
      if (so.data.spriteId != null) spriteId = so.data.spriteId;
      if (so.data.username != null) playerNameEntry.text = so.data.username;
      playerNameEntry.setSelection(0, playerNameEntry.text.length);

      function introUiCleanup():void {
        stage.focus = null;
        playerName = playerNameEntry.text;
        // TODO: for proper cleanup, need to remove event listeners
        preview.removeChild(previewBitmap);
        removeChild(playerNameEntry);
        playerNameEntry = null;
        removeChild(preview);
        removeChild(label);
        removeChild(title);
        setupGameUi();
        cameraZoomTween.onComplete = null;
        cameraZ = 50;
        cameraZoomTween.duration = 5.0;
        cameraZoomTween.ease = Back.easeOut;
        cameraZoomTween.setValue('cameraZ', 0);
      }

      var style:Object = char_spritesheet.makeStyle();
      style.scale = 13;
      style.padding = 6;
      style.bevelWidth = 2;
      style.bevelBlur = 4;
      style.outlineAlpha = 1.0;
      style.outlineBlur = 5;
      var previewBitmap:Bitmap = new Bitmap(new BitmapData(2*style.padding + 8*style.scale, 2*style.padding + 8*style.scale, true, 0x000000));
      style.saturation = 0.9;
      char_spritesheet.drawToBitmap(spriteId, previewBitmap.bitmapData, style);
      previewBitmap.x = 30;
      previewBitmap.y = 130;
      preview.addChild(previewBitmap);

      preview.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void {
          spriteId = int(Math.random()*255);
          char_spritesheet.drawToBitmap(spriteId, previewBitmap.bitmapData, style);
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

          
          if (e.keyCode == 13 /* Enter */ && playerNameEntry.text.length > 0) {
            so.data.username = playerNameEntry.text;
            so.data.spriteId = spriteId;
            so.flush();  // TODO: catch exception in case cookie can't be saved
            introUiCleanup();
          }
        });

      addChild(playerNameEntry);
      addChild(label);
      addChild(title);
      stage.focus = playerNameEntry;
      
      client.sendMessage({type: 'prefetch_map'});
    }

    
    public function setupGameUi():void {
      var mapMask:Shape = new Shape();
      mapMask.graphics.beginFill(0x000000);
      mapMask.graphics.drawRect(0, 0, 400, 400);
      mapMask.graphics.endFill();
      mapParent.mask = mapMask;
      mapMask.x = mapParent.x = 10;
      mapMask.y = mapParent.y = 10;
      addChild(mapParent);
      addChild(mapMask);

      mapArea.addChild(terrainLayer);
      mapArea.addChild(itemLayer);
      mapArea.addChild(characterLayer);

      mapSprite.addChild(mapArea);
      mapSprite.x = 200;
      mapSprite.y = 200;
      mapParent.addChild(mapSprite);
      
      playerStyle.saturation = 0.9;
      char_spritesheet.drawToBitmap(spriteId, playerBitmap.bitmapData, playerStyle);
      playerBitmap.x = -playerBitmap.bitmapData.width/2;
      playerBitmap.y = -playerBitmap.bitmapData.height/2;
      playerSprite.addChild(playerBitmap);
      mapArea.addChild(playerSprite);

      playerIconStyle.scale = 2.0;
      playerIconStyle.padding = 1;
      
      pingTime.x = 10;
      pingTime.y = 10;
      pingTime.width = 400;
      addChild(pingTime);

      inputField.x = 10;
      inputField.y = 410;
      inputField.width = 399;
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
      outputMessages.addSystemText("Arrows to move. Enter to chat. Space to jump.");
      addChild(outputMessages);
      
      // Move this to the top
      removeChild(clickToFocusMessage);
      addChild(clickToFocusMessage);
      
      addEventListener(Event.ENTER_FRAME, onEnterFrame);
      
      stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
      client.sendMessage({type: 'client_identify', name: playerName, sprite_id: spriteId});
      client.sendMessage({type: 'move', from: location, to: location});
      onEnterFrame(null);
    }

    
    public function onEnterFrame(e:Event):void {
      var time:Number = getTimer();
      var f:Number;

      if (animationState) {
        if (animationState.endLocation == null) {
          if (time < animationState.middleTime) {
            f = (time - animationState.beginTime) / (animationState.middleTime - animationState.beginTime);
            camera.x = (1-f) * animationState.beginLocation[0] + f * animationState.middleLocation[0];
            camera.y = (1-f) * animationState.beginLocation[1] + f * animationState.middleLocation[1];
          } else {
            // Eek! We haven't received the response from the server
            // yet. We'll just have to wait.
          }
        } else if (time < animationState.endTime) {
          f = (time - animationState.beginTime) / (animationState.endTime - animationState.beginTime);
          camera.x = (1-f) * animationState.beginLocation[0] + f * animationState.endLocation[0];
          camera.y = (1-f) * animationState.beginLocation[1] + f * animationState.endLocation[1];
        } else {
          camera.x = animationState.endLocation[0];
          camera.y = animationState.endLocation[1];
          animationState = null;
          e = null;  // hack to make sure we still set x,y
        }
      } else {
        camera.x = location[0];
        camera.y = location[1];
        if (_keyQueue) onKeyDown(_keyQueue, true);
      }
      if (animationState != null || e == null) {
        mapArea.x = -mapScale * camera.x;
        mapArea.y = -mapScale * camera.y;
        playerSprite.x = mapScale * (camera.x + 0.5);
        playerSprite.y = mapScale * (camera.y + 0.5);
      }
    }


    public function onKeyDown(e:KeyboardEvent, replay:Boolean = false):void {
      var now:Number;
      // if (!replay) Debug.trace("KEY DOWN", e.keyCode, stage.focus == null? "/stage":"/input");

      var newLoc:Array = [location[0], location[1]];
      if (e.keyCode == 13 /* Enter */) {
        if (stage.focus == inputField) {
          // End text entry by sending to server
          client.sendMessage({type: 'message', message: inputField.text});
          inputField.text = "";
          stage.focus = null;
        } else {
          // Start text entry
          stage.focus = inputField;
        }
      }

      // While entering text, other keys don't apply
      if (stage.focus == inputField) return;

      if (e.keyCode == 32 /* Space */) {
        // TODO: check if we're already jumping, and either ignore, or double jump
        cameraZoomTween.onComplete = function():void {
          cameraZoomTween.onComplete = null;
          cameraZoomTween.ease = Cubic.easeIn;
          cameraZoomTween.duration = 0.2;
          cameraZoomTween.setValue('cameraZ', 0);
        };
        cameraZoomTween.ease = Cubic.easeOut;
        cameraZoomTween.duration = 0.2;
        cameraZoomTween.setValue('cameraZ', 2);
      } else if (e.keyCode == 39 /* RIGHT */) { newLoc[0] += WALK_STEP; }
      else if (e.keyCode == 37 /* LEFT */) { newLoc[0] -= WALK_STEP; }
      else if (e.keyCode == 38 /* UP */) { newLoc[1] -= WALK_STEP; }
      else if (e.keyCode == 40 /* DOWN */) { newLoc[1] += WALK_STEP; }
          
      if (newLoc[0] != location[0] || newLoc[1] != location[1]) {
        if (replay) _keyQueue = null;
        if (!moving && animationState == null) {
          e.updateAfterEvent();
          moving = true;
          client.sendMessage({type: 'move', from: location, to: newLoc});
          now = getTimer();
          animationState = {
            beginLocation: location,
            middleLocation: [0.9*newLoc[0]+0.1*location[0], 0.9*newLoc[1]+0.1*location[1]],
            endLocation: null,  // null until we get the ok from the server
            beginTime: now,
            middleTime: now + 0.9*WALK_TIME,
            endTime: now + WALK_TIME
          };
        } else {
          if (_keyQueue == null) {
            _keyQueue = e;
          }
        }
      }
    }


    private var mapBlocks:Object = {};
    public function handleMessage(message:Object, binaryPayload:ByteArray):void {
      var bitmap:Bitmap;

      if (message.type == 'server_identify') {
        myCreatureId = message.id;
      } else if (message.type == 'move_ok') {
        moving = false;
        if (animationState) {
          animationState.endLocation = message.loc;
        } else {
          // If we don't have an animation state, but received
          // move_ok, we'll just jump to the new location.
          Debug.trace("MOVE_OK with no animation in progress.");
        }
        location = message.loc;

        // Request map tiles corresponding to our new location. Only
        // request the map tiles if we don't already have that block,
        // or if that block is already requested.
        for each (var simblock_id:Object in (message.simblocks_ins || [])) {
            var simblock_hash:String = simblock_id.toString();
            if (mapBlocks[simblock_hash] == null) {
              mapBlocks[simblock_hash] = {};  // Pending
              client.sendMessage({type: 'map_tiles', simblock_id: simblock_id});
            }
          }

        // TODO: clear map bitmap for blocks in simblocks_del
        
        // HACK: if a movement was delayed because we were already
        // moving, trigger the new movement
        if (_keyQueue) onKeyDown(_keyQueue, true);
      } else if (message.type == 'map_tiles') {
        var i:int, tileId:int, x:int, y:int;
        if (colorMap.length == 0) buildColorMap();
        i = 0;
        var bmp:BitmapData = new BitmapData(message.right-message.left, message.bottom-message.top, false);
        for (x = message.left; x < message.right; x++) {
          for (y = message.top; y < message.bottom; y++) {
            tileId = binaryPayload[i++];
            bmp.setPixel(x - message.left, y - message.top, colorMap[tileId]);
          }
        }
        bmp.lock();

        bitmap = new Bitmap(bmp);
        bitmap.scaleX = bitmap.scaleY = mapScale;
        bitmap.x = mapScale * message.left;
        bitmap.y = mapScale * message.top;
        
        simblock_hash = message.simblock_id.toString();
        mapBlocks[simblock_hash].bitmap = bitmap;
        terrainLayer.addChild(bitmap);
      } else if (message.type == 'item_ins') {
        bitmap = new Bitmap(new BitmapData(playerBitmap.width, playerBitmap.height, true, 0x00000000));
        tile_spritesheet.drawToBitmap(message.obj.sprite_id, bitmap.bitmapData, playerStyle);
        bitmap.x = mapScale * message.obj.loc[0] - playerStyle.padding;
        bitmap.y = mapScale * message.obj.loc[1] - playerStyle.padding;
        itemLayer.addChild(bitmap);

        var loc:String = message.obj.loc.toString();
        if (items[loc] != null) Debug.trace("ERROR: ins item, already exists at ", loc);
        items[loc] = {sprite: bitmap, obj: message.obj};
      } else if (message.type == 'item_del') {
        loc = message.obj.loc.toString();
        if (items[loc] == null) Debug.trace("ERROR: del item, none at ", loc);
        itemLayer.removeChild(items[loc].sprite);
        delete items[loc];
      } else if (message.type == 'creature_ins') {
        // HACK: until we separate server's player representation from connection
        message.obj.sprite_id = message.obj.sprite_id || message.obj.spriteId;

        bitmap = new Bitmap(new BitmapData(playerBitmap.width, playerBitmap.height, true, 0x00000000));
        char_spritesheet.drawToBitmap(message.obj.sprite_id, bitmap.bitmapData, playerStyle);
        bitmap.x = mapScale * message.obj.loc[0] - playerStyle.padding;
        bitmap.y = mapScale * message.obj.loc[1] - playerStyle.padding;
        characterLayer.addChild(bitmap);
        if (message.obj.id == myCreatureId) bitmap.visible = false;  // it's me!
        if (creatures[message.obj.id] != null) Debug.trace("ERROR: ins creature, already exists at ", message.obj.id);
        creatures[message.obj.id] = {sprite: bitmap, obj: message.obj};
      } else if (message.type == 'creature_del') {
        if (creatures[message.obj.id] == null) Debug.trace("ERROR: del creature, none at ", message.obj.id);
        characterLayer.removeChild(creatures[message.obj.id].sprite);
        delete creatures[message.obj.id];
      } else if (message.type == 'creature_move') {
        if (creatures[message.obj.id] == null) Debug.trace("ERROR: move creature, none at ", message.obj.id);
        bitmap = creatures[message.obj.id].sprite;
        bitmap.x = mapScale * message.obj.loc[0] - playerStyle.padding;
        bitmap.y = mapScale * message.obj.loc[1] - playerStyle.padding;
      } else if (message.type == 'messages') {
        for each (var chat:Object in message.messages) {
            var iconSize:Number = 2*playerIconStyle.padding + 8*playerIconStyle.scale;
            var icon:Bitmap = new Bitmap(new BitmapData(iconSize, iconSize, true, 0xffff00ff));
            char_spritesheet.drawToBitmap(chat.sprite_id, icon.bitmapData, playerIconStyle);
            outputMessages.addChat(icon, chat.from, chat.systemtext, chat.usertext);
        }
      } else if (message.type == 'pong') {
        pingTime.text = "ping time: " + (getTimer() - message.timestamp) + "ms" + " recv: " + client._bytesPerSecond + " bytes/second";
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


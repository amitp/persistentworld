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

  [SWF(width="600",height="500")]
  public class gameclient extends Sprite {
    static public var TILES_ON_SCREEN:int = 13;
    static public var TILE_PADDING:int = 3;
    static public var WALK_ADJACENT_TIME:Number = 150;
    static public var WALK_DIAGONAL_TIME:Number = WALK_ADJACENT_TIME * Math.sqrt(2);
    
    // The map area contains all the tile blocks and other players,
    // positioned in absolute coordinate space. Moving the camera
    // means moving and zooming the map area within the map
    // parent. You can think of the map parent as being a "window" on
    // top of the map area. The map area is divided into two layers:
    // terrainLayer, objectLayer.  TODO: multiple objects may be in
    // the object layer in the same grid space; figure out how to display.
    static public var mapScale:Number = 3.0 * 8;
    public var terrainLayer:Sprite = new Sprite();
    public var objectLayer:Sprite = new Sprite();
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
    public var myCreatureId:String = "";
    public var playerStyle:Object = char_spritesheet.makeStyle();
    public var playerIconStyle:Object = char_spritesheet.makeStyle();
    public var playerBitmap:Bitmap = new Bitmap(new BitmapData(2*2 + 8*3, 2*2 + 8*3, true, 0x00000000));
    public var playerSprite:Sprite = new Sprite();

    // Only present during the login, and null at other times:
    public var playerNameEntry:TextField = null;
    
    public var playerLocation:Point = new Point(945, 1220);
    public var moving:Boolean = false;
    
    public var animationState:Object = null;

    // Map objects:
    public var contents:Object = {};  // {block or obj id: [obj, ...]}
    public var objects:Object = {};  // {obj id: obj}
    public var tweens:Object = {};  // {obj id: GTween}
    public var representations:Object = {};  // {block or obj id: Bitmap}

    public var colorMap:Array = [];
    public var client:Client = new Client();
    public var pingTime:TextField = new TextField();
    public var inputField:TextField = new TextField();
    public var outputMessages:OutputMessageBox = new OutputMessageBox(400, 200);

    // Actions: an array from keyCode to the action object sent by the server
    public var keyActions:Array = [];
    
    // Server message handlers
    private var handlers:Object = {
      'server_identify': handle_server_identify,
      'move_ok': handle_move_ok,
      's_jump': handle_s_jump,
      's_actions': handle_s_actions,
      'map_tiles': handle_map_tiles,
      'obj_ins': handle_obj_ins,
      'obj_del': handle_obj_del,
      'obj_move': handle_obj_move,
      'messages': handle_messages,
      'handle_pong': handle_pong
    };
    
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
          forgetKeysHeldDown();
          tween.duration = 0.15;
          tween.setValue('alpha', 0.0);
          if (playerNameEntry != null) stage.focus = playerNameEntry;
        });
      stage.addEventListener(Event.DEACTIVATE, function (e:Event):void {
          forgetKeysHeldDown();
          clickToFocusMessage.visible = true;
          tween.duration = 1.5;
          tween.setValue('alpha', 1.0);
        });

      client.addEventListener(ServerMessageEvent.SERVER_MESSAGE, function (e:ServerMessageEvent):void {
          handlers[e.message.type].call(this, e.message, e.binary);
        });
      client.addEventListener(Event.CONNECT, function (e:Event):void {
          // TODO: remove 'Connecting' status and use activate/deactivate
        });
      client.addEventListener(Event.CLOSE, function (e:Event):void {
          outputMessages.addSystemText("Lost connection. Try reloading.");
        });
      client.addEventListener(IOErrorEvent.IO_ERROR, function (e:IOErrorEvent):void {
          outputMessages.addSystemText("I/O Error:" + e.toString());
        });
      client.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function (e:SecurityErrorEvent):void {
          outputMessages.addSystemText("Security Error:" + e.toString());
        });
      var timer:Timer = new Timer(50, 1);
      timer.addEventListener(TimerEvent.TIMER,
                             function (e:TimerEvent):void {
                               client.connect();
                             });
      timer.start();
      
      var debugMode:Boolean = false;
      CONFIG::debugging {
        debugMode = true;
      }

      if (debugMode) {
        spriteId = 65;
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
      mapArea.addChild(objectLayer);

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
      stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
        
      client.sendMessage({type: 'client_identify', name: playerName, sprite_id: spriteId});
      client.sendMessage({type: 'move', x: playerLocation.x, y: playerLocation.y});
      onEnterFrame(null);
    }

    
    public function onEnterFrame(e:Event):void {
      var time:Number = getTimer();
      var f:Number;

      if (animationState) {
        if (animationState.end == null) {
          if (time < animationState.middleTime) {
            f = (time - animationState.beginTime) / (animationState.middleTime - animationState.beginTime);
            camera.x = (1-f) * animationState.begin.x + f * animationState.middle.x;
            camera.y = (1-f) * animationState.begin.y + f * animationState.middle.y;
          } else {
            // Eek! We haven't received the response from the server
            // yet. We'll just have to wait.
          }
        } else if (time < animationState.endTime) {
          f = (time - animationState.beginTime) / (animationState.endTime - animationState.beginTime);
          camera.x = (1-f) * animationState.begin.x + f * animationState.end.x;
          camera.y = (1-f) * animationState.begin.y + f * animationState.end.y;
        } else {
          camera.x = animationState.end.x;
          camera.y = animationState.end.y;
          animationState = null;
          e = null;  // HACK: make sure we still set x,y
        }
      } else {
        camera.x = playerLocation.x;
        camera.y = playerLocation.y;
        checkKeyMovement();
      }
      if (animationState != null || e == null) {
        mapArea.x = -mapScale * camera.x;
        mapArea.y = -mapScale * camera.y;
        playerSprite.x = mapScale * (camera.x + 0.5);
        playerSprite.y = mapScale * (camera.y + 0.5);
      }
    }


    // Arrow key handling: we track which keys are held down and
    // trigger movement. TODO: since both keys aren't pressed at
    // exactly the same time, we end up triggering non-diagonal
    // movement for one space before diagonal kicks in; we'd want to
    // delay movement until onEnterFrame to capture the diagonal.
    private var _keyDown:Array = [];  // keyCode -> boolean

    public function forgetKeysHeldDown():void {
      _keyDown = [];
    }
    
    public function checkKeyMovement():void {
      var now:Number, walkTime:Number;
      var dx:int = 0, dy:int = 0;
      
      // We won't move unless the map has keyboard focus, and we're not moving
      if (stage.focus != null) return;
      if (moving) return;
      if (animationState != null) return;
      
      if (_keyDown[39] /* RIGHT */) { dx += 1; }
      if (_keyDown[37] /* LEFT */) { dx -= 1; }
      if (_keyDown[38] /* UP */) { dy -= 1; }
      if (_keyDown[40] /* DOWN */) { dy += 1; }

      if (dx != 0 || dy != 0) {
        if (dx != 0 && dy != 0) {
          walkTime = WALK_DIAGONAL_TIME;
        } else {
          walkTime = WALK_ADJACENT_TIME;
        }
        
        moving = true;
        keyActions = [];  // invalidate actions because they are for the current location
        client.sendMessage({type: 'move', x: playerLocation.x + dx, y: playerLocation.y + dy});
        now = getTimer();
        animationState = {
          begin: {x: playerLocation.x, y: playerLocation.y},
          middle: {x: playerLocation.x + 0.9*dx, y: playerLocation.y + 0.9*dy},
          end: null,  // null until we get the ok from the server
          beginTime: now,
          middleTime: now + 0.9*walkTime,
          endTime: now + walkTime
        };
      }
    }
    
    public function onKeyUp(e:KeyboardEvent):void {
      _keyDown[e.keyCode] = false;
      checkKeyMovement();
    }
    
    public function onKeyDown(e:KeyboardEvent, replay:Boolean = false):void {
      _keyDown[e.keyCode] = true;
      checkKeyMovement();
      
      if (e.keyCode == 13 /* Enter */) {
        forgetKeysHeldDown();
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
      if (stage.focus == inputField) {
        forgetKeysHeldDown();
        return;
      }

      if (keyActions[e.keyCode]) {
        Debug.trace("ACTION " + JSON.encode(keyActions[e.keyCode]));
        client.sendMessage({
              type: 'c_action',
              verb: keyActions[e.keyCode].verb,
              obj: keyActions[e.keyCode].obj
              });
      }
      
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
        client.sendMessage({type: 'c_jump'});
      }
    }


    private function handle_server_identify(message:Object, binaryPayload:ByteArray):void {
      myCreatureId = message.id;
    }

    private function handle_move_ok(message:Object, binaryPayload:ByteArray):void {
      var chunk_id:String;
      
      moving = false;
      if (animationState) {
        // TODO: we ignore message.loc (chunk id)
        animationState.end = {x: message.x, y: message.y};
      } else {
        // If we don't have an animation state, but received
        // move_ok, we'll just jump to the new location.
        Debug.trace("MOVE_OK with no animation in progress.");
      }
      playerLocation.x = message.x;
      playerLocation.y = message.y;

      // Request map tiles corresponding to our new location. Only
      // request the map tiles if we don't already have that block,
      // or if that block is already requested.
      if (message.chunks_ins != null) {
        for each (chunk_id in message.chunks_ins) {
            if (!representations[chunk_id]) {
              representations[chunk_id] = {};  // Pending
              client.sendMessage({type: 'map_tiles', chunk_id: chunk_id});
            }
          }
      }
      // TODO: clear map bitmap for blocks in chunks_del
      checkKeyMovement();
    }

    private function handle_s_jump(message:Object, binaryPayload:ByteArray):void {
      var tween:GTween;
      if (message.id != myCreatureId && representations[message.id]) {
        tween = new GTween(representations[message.id], 0.2, {}, {});
        tween.onComplete = function():void {
          tween.onComplete = null;
          tween.ease = Cubic.easeIn;
          tween.setValues({scaleX: 1.0, scaleY: 1.0});
        };
        tween.ease = Cubic.easeOut;
        tween.setValues({scaleX: 1.1, scaleY: 1.1});
      }
    }

    private function handle_s_actions(message:Object, _:ByteArray):void {
      // For now, display the action menu in the chat window. TODO:
      // display the set of actions in a separate UI area, and clear
      // it each time the menu is rewritten. TODO: if the player
      // hasn't moved, try to reuse the same keys for recently
      // displayed actions.
      var action:Object, i:int, keyCode:int;
      keyActions = [];
      for (i = 0; i < message.actions.length; i++) {
        action = message.actions[i];
        keyCode = '1'.charCodeAt(0) + i;
        keyActions[keyCode] = action;
        outputMessages.addChat(null, "Press [" + String.fromCharCode(keyCode) + "]", " to ", action.text);
      }
    }
    
    private function handle_map_tiles(message:Object, binaryPayload:ByteArray):void {
      var i:int, tileId:int, x:int, y:int;
      var bmp:BitmapData, bitmap:Bitmap;
      
      if (colorMap.length == 0) buildColorMap();
      i = 0;
      bmp = new BitmapData(message.right-message.left, message.bottom-message.top, false);
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
        
      representations[message.chunk_id].bitmap = bitmap;
      terrainLayer.addChild(bitmap);
    }

    private function handle_obj_ins(message:Object, _:ByteArray):void {
      var bitmap:Bitmap;
      
      bitmap = new Bitmap(new BitmapData(playerBitmap.width, playerBitmap.height, true, 0x00000000));
      if (message.obj.sprite_id >= 0x1000) {
        tile_spritesheet.drawToBitmap(message.obj.sprite_id - 0x1000, bitmap.bitmapData, playerStyle);
      } else {
        char_spritesheet.drawToBitmap(message.obj.sprite_id, bitmap.bitmapData, playerStyle);
      }
      bitmap.x = mapScale * message.obj.x - playerStyle.padding;
      bitmap.y = mapScale * message.obj.y - playerStyle.padding;
      objectLayer.addChild(bitmap);
      if (message.obj.id == myCreatureId) bitmap.visible = false;  // it's me!
      if (objects[message.obj.id] != null) Debug.trace("ERROR: obj_ins, already exists at ", message.obj.id);
      objects[message.obj.id] = message.obj;
      tweens[message.obj.id] = null;
      representations[message.obj.id] = bitmap;
    }

    private function handle_obj_del(message:Object, _:ByteArray):void {
      if (!objects[message.obj_id]) Debug.trace("ERROR: obj_del, none at ", message.obj_id);
      objectLayer.removeChild(representations[message.obj_id]);
      delete objects[message.obj_id];
      delete tweens[message.obj_id];
      delete representations[message.obj_id];
    }

    private function handle_obj_move(message:Object, _:ByteArray):void {
      var tween:GTween;
      
      if (!objects[message.obj_id]) Debug.trace("ERROR: obj_move, none at ", message.obj_id);
      tween = tweens[message.obj_id];
      if (tween == null) {
        tween = new GTween(representations[message.obj_id], 0.2, {}, {});
        tweens[message.obj_id] = tween;
      }
      tween.setValue('x', mapScale * message.x - playerStyle.padding);
      tween.setValue('y', mapScale * message.y - playerStyle.padding);
    }
    
    private function handle_messages(message:Object, _:ByteArray):void {
      var chat:Object, iconSize:Number, icon:Bitmap;
      
      for each (chat in message.messages) {
          if (chat.from) {
            iconSize = 2*playerIconStyle.padding + 8*playerIconStyle.scale;
            icon = new Bitmap(new BitmapData(iconSize, iconSize, true, 0xffff00ff));
            char_spritesheet.drawToBitmap(chat.sprite_id, icon.bitmapData, playerIconStyle);
            outputMessages.addChat(icon, chat.from, chat.systemtext, chat.usertext);
          } else {
            outputMessages.addSystemText(chat.systemtext + chat.usertext);
          }
        }
    }

    private function handle_pong(message:Object, _:ByteArray):void {
      pingTime.text = ("ping time: " + (getTimer() - message.timestamp) + "ms"
                       + " recv: " + client._bytesPerSecond + " bytes/second");
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


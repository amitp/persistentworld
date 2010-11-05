// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

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

    static public var serverAddress:String = null;
    static public var serverPort:int = 8001;

    static public var BITMAPSCALE:Number = 5.0;
    public var mapBitmap:BitmapData = new BitmapData(2048, 2048);
    public var colorMap:Array = [];
    
    public function client() {
      stage.frameRate = 30;
      
      var b:Bitmap = new Bitmap(mapBitmap);
      b.scaleX = 1.0/BITMAPSCALE;
      b.scaleY = 1.0/BITMAPSCALE;
      b.smoothing = true;
      addChild(b);
      
      addChild(new Debug(this));

      var buffer:ByteArray = new ByteArray();

      stage.addEventListener(Event.ACTIVATE, onActivate);
      stage.addEventListener(Event.DEACTIVATE, onDeactivate);
      
      socket.addEventListener(Event.CONNECT, function (e:Event):void {
          Debug.trace("CONNECT -- click to activate");
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
                                var previousPosition:int = buffer.position;
                                socket.readBytes(buffer, buffer.length, socket.bytesAvailable);

                                while (buffer.bytesAvailable >= 8) {
                                  // It's long enough that we can read the sizes
                                  var sizeBuffer:ByteArray = new ByteArray();
                                  buffer.readBytes(sizeBuffer, 0, 4);
                                  var jsonLength:int = binaryToInt32LittleEndian(sizeBuffer);
                                  buffer.readBytes(sizeBuffer, 0, 4);
                                  var binaryLength:int = binaryToInt32LittleEndian(sizeBuffer);

                                  // Sanity check the lengths
                                  if (!(8 <= jsonLength && jsonLength <= 10000)) {
                                    Debug.trace("ERROR: jsonLength corrupt? ", jsonLength);
                                    socket.close();
                                    return;
                                  }
                                  if (!(0 <= binaryLength && binaryLength <= 10000000)) {
                                    Debug.trace("ERROR: binaryLength corrupt? ", binaryLength);
                                    socket.close();
                                    return;
                                  }

                                  if (buffer.bytesAvailable >= jsonLength + binaryLength) {
                                    // The entire message has arrived
                                    var jsonMessage:String = buffer.readUTFBytes(jsonLength);
                                    var binaryMessage:ByteArray = new ByteArray();
                                    buffer.readBytes(binaryMessage, 0, binaryLength);
                                    handleMessage(JSON.decode(jsonMessage), binaryMessage);
                                    previousPosition = buffer.position;
                                  } else {
                                    // We need to wait. Rewind the
                                    // read position back to where
                                    // we were, and break out of the
                                    // loop.
                                    buffer.position = previousPosition;
                                    break;
                                  }
                                }
                                      
                                if (buffer.position == buffer.length && buffer.position > 0) {
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

    // Conversion from int to little-endian 32-bit binary and back
    static public function binaryToInt32LittleEndian(buffer:ByteArray):int {
      return buffer[0] | (buffer[1] << 8) | (buffer[2] << 16) | (buffer[3] << 24);
    }

    static public function int32ToBinaryLittleEndian(value:int):ByteArray {
      var bytes:ByteArray = new ByteArray();
      bytes.writeByte(value & 0xff);
      bytes.writeByte((value >> 8) & 0xff);
      bytes.writeByte((value >> 16) & 0xff);
      bytes.writeByte((value >> 24) & 0xff);
      return bytes;
    }
                              
    public function onActivate(e:Event):void {
      Debug.trace("ACTIVATE -- got focus, now move the mouse around");
      // NOTE: the Debug panel is eating up the mouse events, so we grab from stage instead
      stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
      pingTimer.start();
    }

    public function onDeactivate(e:Event):void {
      Debug.trace("DEACTIVATE -- lost focus, click to activate");
      stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
      pingTimer.stop();
    }

    public function onMouseMove(e:MouseEvent):void {
      // sendMessage({type: 'mouse_move', id: clientId, x: e.localX, y: e.localY});
      var radius:int = 20 * BITMAPSCALE;
      sendMessage({type: 'map_tiles', timestamp: getTimer(), left: e.localX*BITMAPSCALE-radius, right: e.localX*BITMAPSCALE+radius, top: e.localY*BITMAPSCALE-radius, bottom: e.localY*BITMAPSCALE+radius});
    }

    public function sendMessage(message:Object, binaryPayload:ByteArray=null):void {
      var jsonMessage:String = JSON.encode(message);
      var packet:ByteArray = new ByteArray();

      // We don't know how many bytes the jsonMessage will use, until
      // we write it to the message, so we'll come back and fix up the
      // size afterwards
      packet.writeBytes(int32ToBinaryLittleEndian(0));
      packet.writeBytes(int32ToBinaryLittleEndian(binaryPayload? binaryPayload.length : 0));
      packet.writeUTFBytes(jsonMessage);
      var jsonLength:int = packet.position - 8;
      if (binaryPayload) packet.writeBytes(binaryPayload);

      // Now fix up the jsonMessage size
      packet.position = 0;
      packet.writeBytes(int32ToBinaryLittleEndian(jsonLength));

      socket.writeBytes(packet);
      socket.flush();
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
      
    public function onTimer(e:TimerEvent):void {
      // sendMessage({type: 'ping', timestamp: getTimer()});
    }
  }
}


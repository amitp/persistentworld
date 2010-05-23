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
    }
    
    public function handleMessage(message:Object, binaryPayload:ByteArray):void {
      // Debug.trace("HANDLE MESSAGE", msg);
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


// Game network client
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import amitp.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;
  import com.adobe.serialization.json.*;
  
  public class Client extends EventDispatcher {
    public var socket:Socket = new Socket();
    public var buffer:ByteArray = new ByteArray();
    public var bytesReceived:int = 0;
    public var pingTimerDelayWhileActive:Number = 1000/7;
    public var pingTimerDelayWhileInactive:Number = 1000/1;
    public var pingTimer:Timer = new Timer(1000/1, 0);

    // This class dispatches events:
    // * Event.CONNECT on connection to the server
    // * Event.CLOSE on disconnection
    // * Client.NETWORK_MESSAGE on message receive
    // * IOErrorEvent.IO_ERROR on socket error
    // * SecurityErrorEvent.SECURITY_ERROR on socket security error

    private var _sendQueue:Array = [];  // Used only until we connect
    
    public function Client() {
      socket.addEventListener(Event.ACTIVATE, this.activate);
      socket.addEventListener(Event.DEACTIVATE, this.deactivate);
    }

    public function connect(serverAddress:String = null, serverPort:int = 8001):void {
      socket.addEventListener(Event.CONNECT, this.onConnect);
      socket.addEventListener(Event.CLOSE, this.onClose);
      socket.addEventListener(IOErrorEvent.IO_ERROR, this.dispatchEvent);
      socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this.dispatchEvent);
      socket.addEventListener(ProgressEvent.SOCKET_DATA, this.onSocketData);
      socket.connect(serverAddress, serverPort);
    }

    
    private function onConnect(e:Event):void {
      while (_sendQueue.length > 0) {
        _sendMessage(_sendQueue[0][0], _sendQueue[0][1]);
        _sendQueue.shift();
      }
      pingTimer.addEventListener(TimerEvent.TIMER, onTimer);
      pingTimer.start();
      dispatchEvent(e);
    }
    

    private function onClose(e:Event):void {
      pingTimer.removeEventListener(TimerEvent.TIMER, onTimer);
      dispatchEvent(e);
    }

    
    private function onSocketData(e:ProgressEvent):void {
      var previousPosition:int = buffer.position;
      if (socket.bytesAvailable == 0) {
        Debug.trace("ERROR: SOCKET_DATA event has bytesAvailable == 0");
        return;
      }

      bytesReceived += socket.bytesAvailable;
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
          if (binaryLength > 0) {
            // NOTE: we don't want
            // binaryLength == 0 to get
            // passed in to readBytes()
            // because that tells it to read
            // everything.
            buffer.readBytes(binaryMessage, 0, binaryLength);
          }

          var message:Object = JSON.decode(jsonMessage);
          var event:ServerMessageEvent = new ServerMessageEvent(message, binaryMessage);
          if (message.type == 'pong') {
            _lastPingTime = getTimer() - message.timestamp;
          } else {
            // Debug.trace("RECV", binaryMessage.length, jsonMessage);
          }
          this.dispatchEvent(event);
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

      dispatchEvent(e);
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

    
    private function activate(e:Event):void {
      pingTimer.delay = pingTimerDelayWhileActive;
      if (socket.connected && !pingTimer.running) pingTimer.start();
    }

    
    private function deactivate(e:Event):void {
      pingTimer.delay = pingTimerDelayWhileInactive;
      if (socket.connected && !pingTimer.running) pingTimer.start();
    }


    public function sendMessage(message:Object, binaryPayload:ByteArray=null):void {
      if (socket.connected) {
        _sendMessage(message, binaryPayload);
      } else {
        _sendQueue.push([message, binaryPayload]);
      }
    }

    
    private function _sendMessage(message:Object, binaryPayload:ByteArray):void {
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

    private var _lastPingTime:Number = 0.0;
    private var _lastBytesReceived:int = 0;
    public var _bytesPerSecond:Number = 0.0;
    public function onTimer(e:TimerEvent):void {
      if (socket.connected) {
        sendMessage({type: 'ping', timestamp: getTimer(), ping_time: (_lastPingTime > 0.0)? _lastPingTime : null});
        _bytesPerSecond = 1000 * (bytesReceived - _lastBytesReceived) / pingTimer.delay;
        _lastBytesReceived = bytesReceived;
      }
    }
  }
}


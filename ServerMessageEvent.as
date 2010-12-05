// Event dispatched when the server sends a message to the client
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.events.Event;
  import flash.utils.ByteArray;
  
  public class ServerMessageEvent extends Event {
    static public var SERVER_MESSAGE:String = 'server-message';
    
    public var message:Object;
    public var binary:ByteArray;

    public function ServerMessageEvent(m:Object, b:ByteArray) {
      super(SERVER_MESSAGE);
      message = m;
      binary = b;
    }
  }
}

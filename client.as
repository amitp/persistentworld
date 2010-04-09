// Basic Flash client for a game
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.display.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;
  
  public class client extends Sprite {

    public function client() {
      addChild(new Debug(this));
      
      var timer:Timer = new Timer(1000/60, 0);
      timer.addEventListener(TimerEvent.TIMER, jitter);
      timer.start();
    }

    public function jitter(e:TimerEvent):void {
    }
  }
}


// Widget to show a series of game messages
// Author: amitp@cs.stanford.edu
// License: MIT

// TODO: add scrollback capability

package {
  import amitp.*;
  import flash.display.DisplayObject;
  import flash.display.Sprite;
  import flash.geom.Rectangle;
  import flash.text.engine.*;
  import com.gskinner.motion.GTween;

  public class OutputMessageBox extends Sprite {
    // The messages are represented as child Sprites. Each one
    // contains a rendered TextBlock.  We remember where we need to
    // add the next sprite, and what the overall container size is:
    private var nextYPosition:Number = 0.0;
    private var maxWidth:Number;
    private var maxHeight:Number;
    
    // General configuration:
    static public var MARGIN:Number = 2.0;
    static public var LINE_SPACING:Number = 4.0;
    static public var FONT:String = "Helvetica,Arial,_sans";

    // Text formatting:
    private var systemFormat:ElementFormat = new ElementFormat();
    private var fromFormat:ElementFormat = new ElementFormat();
    private var separatorFormat:ElementFormat = new ElementFormat();
    private var textFormat:ElementFormat = new ElementFormat();

    // Scrolling with a tween:
    public var scrollPositionTween:GTween = new GTween(this, 0.1, {}, {});
    public function get scrollPosition():Number { return scrollRect.y; }
    public function set scrollPosition(position:Number):void {
      // Flash note: Set .y instead of .top to preserve the rectangle
      // height. Assign the rect back to scrollRect to trigger the
      // setter method.
      var rect:Rectangle = scrollRect;
      rect.y = position;
      scrollRect = rect;
    }

    
    // The constructor requires the expected size of this element so
    // that we can set up a scroll box and clipping.
    public function OutputMessageBox(w:Number, h:Number) {
      var font1:FontDescription = new FontDescription(FONT, FontWeight.BOLD);
      var font2:FontDescription = new FontDescription(FONT);

      maxWidth = w;
      maxHeight = h;
      scrollRect = new Rectangle(0, 0, w, h);
      
      systemFormat.fontSize = 14;
      systemFormat.color = 0x0000ff;
      systemFormat.fontDescription = font1;
      
      fromFormat.fontSize = 12;
      fromFormat.color = 0x009966;
      fromFormat.fontDescription = font1;
      separatorFormat.fontSize = 12;
      separatorFormat.color = 0x999999;
      separatorFormat.fontDescription = font2;
      textFormat.fontSize = 12;
      textFormat.fontDescription = font2;
    }


    // Add a text block with plain text from the game system
    public function addSystemText(text:String):void {
      var textBlock:TextBlock = new TextBlock();
      textBlock.content = new TextElement(text, systemFormat);
      addTextBlock(textBlock);
    }


    // Add a text block with chat text from a creature
    public function addChat(icon:DisplayObject, from:String, systemText:String, userText:String):void {
      var v:Vector.<ContentElement> = new Vector.<ContentElement>();
      if (icon != null) v.push(new GraphicElement(icon, icon.width+2, icon.height-LINE_SPACING/2, fromFormat));
      v.push(new TextElement(from, fromFormat),
             new TextElement(systemText, separatorFormat),
             new TextElement(userText, textFormat));
      var groupElement:GroupElement = new GroupElement(v);
      var textBlock:TextBlock = new TextBlock();
      textBlock.content = groupElement;
      addTextBlock(textBlock);
    }


    // Remove any children that are completely off screen.
    private function removePastTextBlocks():void {
      // This loop has two exit conditions: either there are
      // no children left, or the first child is in the scroll
      // rectangle.
      while (true) {
        if (numChildren == 0) break;
        
        var rect:Rectangle = getChildAt(0).getBounds(this);
        if (rect.bottom >= scrollRect.top) break;

        removeChildAt(0);
      }
    }

    
    // Add the text block to the sprite by creating a parent sprite
    // and splitting the text block into individual text lines. Adjust
    // the scroll position if necessary.
    private function addTextBlock(textBlock:TextBlock):void {
      removePastTextBlocks();
      
      var block:Sprite = new Sprite();
      var firstLineExtra:Number = 20;
      var lineLength:Number = maxWidth - firstLineExtra - 2*MARGIN;
      var xPosition:Number = MARGIN;
      var textLine:TextLine = textBlock.createTextLine(null, lineLength + firstLineExtra);

      while (textLine) {
        block.addChild(textLine);
        textLine.x = xPosition;
        nextYPosition += textLine.height+LINE_SPACING;
        textLine.y = nextYPosition;
        xPosition = firstLineExtra + MARGIN;
        textLine = textBlock.createTextLine(textLine, lineLength);
      }

      addChild(block);

      // We want nextYPosition to be the bottom of the scroll
      // rectangle, or above.
      if (nextYPosition > scrollRect.bottom - LINE_SPACING) {
        scrollPositionTween.setValue('scrollPosition', nextYPosition - maxHeight + LINE_SPACING);
      }
    }
  }
}


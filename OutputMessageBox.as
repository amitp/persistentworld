// Widget to show a series of game messages
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import amitp.*;
  import flash.display.DisplayObject;
  import flash.display.Sprite;
  import flash.geom.Rectangle;
  import flash.text.engine.*;

  public class OutputMessageBox extends Sprite {
    // The messages are represented as child Sprites. Each one
    // contains a rendered TextBlock.  We remember where we need to
    // add the next sprite:
    public var nextYPosition:Number = 0.0;

    // General configuration
    static public var MARGIN:Number = 2.0;
    static public var LINE_SPACING:Number = 8.0;
    static public var FONT:String = "Helvetica,Arial,_sans";

    // Text formatting:
    private var systemFormat:ElementFormat = new ElementFormat();
    private var fromFormat:ElementFormat = new ElementFormat();
    private var separatorFormat:ElementFormat = new ElementFormat();
    private var textFormat:ElementFormat = new ElementFormat();

    // The constructor requires the expected size of this element so
    // that we can set up a scroll box and clipping.
    public function OutputMessageBox(w:Number, h:Number) {
      var font1:FontDescription = new FontDescription(FONT, FontWeight.BOLD);
      var font2:FontDescription = new FontDescription(FONT);

      systemFormat.fontSize = 11;
      systemFormat.color = 0x0000ff;
      systemFormat.fontDescription = font1;
      
      fromFormat.fontSize = 11;
      fromFormat.color = 0x009966;
      fromFormat.fontDescription = font1;
      separatorFormat.fontSize = 11;
      separatorFormat.color = 0x999999;
      separatorFormat.fontDescription = font2;
      textFormat.fontSize = 11;
      textFormat.fontDescription = font2;
      textFormat.digitCase = DigitCase.OLD_STYLE;

      // TODO: It seems like the text engine produces completely
      // messed up scaled text unless we draw *something* large onto
      // this sprite. I don't know if this is a Flash bug or if I'm
      // doing something wrong.
      graphics.beginFill(0xeeeeee, 0.1);
      graphics.drawRect(0, 0, w, h);
      graphics.endFill();

      width = w;
      height = h;
      
      scrollRect = new Rectangle(0, 0, w, h);
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
      if (icon != null) v.push(new GraphicElement(icon, icon.width, icon.height-LINE_SPACING/2, fromFormat));
      v.push(new TextElement(from, fromFormat),
             new TextElement(systemText, separatorFormat),
             new TextElement(userText, textFormat));
      var groupElement:GroupElement = new GroupElement(v);
      var textBlock:TextBlock = new TextBlock();
      textBlock.content = groupElement;
      addTextBlock(textBlock);
    }


    // Add the text block to the sprite by creating a parent sprite
    // and splitting the text block into individual text lines. Adjust
    // the scroll position if necessary.
    private function addTextBlock(textBlock:TextBlock):void {
      var block:Sprite = new Sprite();

      var firstLineExtra:Number = 20;
      var lineLength:Number = width - firstLineExtra - 2*MARGIN;
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
      if (nextYPosition > height-8) {
        var rect:Rectangle = scrollRect;
        rect.y = nextYPosition - height-LINE_SPACING;
        scrollRect = rect;
        // TODO: remove old children that are completely off screen now
      }
    }
  }
}


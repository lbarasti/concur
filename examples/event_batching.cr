require "../src/concur"

record KeyboardEvent, id : Int32, key : Char
record MouseEvent, id : Int32, pos : {Int32, Int32}

keypress = Channel(KeyboardEvent).new
mouse_click = Channel(MouseEvent).new

spawn(name: "event simulator") do
  loop do
    sleep rand
    rand < 0.3 ?
      keypress.send(KeyboardEvent.new(rand(1024), ('a'..'z').sample)) :
      mouse_click.send(MouseEvent.new(rand(1024), {rand(60), rand(80)}))
  end
end

pp keypress.merge(mouse_click)
  .batch(size: 5, interval: 1.seconds)
  .scan({"", {0,0}}) { |state, events|
    events.reduce(state) { |s, e|
      case e
      in MouseEvent
        {s[0], e.pos}
      in KeyboardEvent
        {s[0] + e.key, s[1]}
      end
    }
  }
  .take 10


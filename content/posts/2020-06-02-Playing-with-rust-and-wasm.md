---
title: "Playing With Rust and Wasm"
date: 2020-06-02T21:52:04+02:00
draft: true
---

I have read a lot about how Wasm is great for porting non-JS languages into the browser and maybe even into a general Lambda runtime.
Also better security and ability to compile libraries into Wasm and use them in other languages.
So I wanted to try it and document my experience using Rust+Wasm to build a game of life using wasm (before knowing about the book).

**TLDR:** Read the [official rust+wasm introduction][wasm-life-introduction] instead of reading about me stumbling around.

## (Wasm? Rust?)
- wasm is like assembler for the browser
- stronger security guarantees built into the language
- currently mostly browser, there are initiatives to provide a runtime for bare-metal (kinda jvm/graal? like)
- rust is a systems programming language with focus on safety and performance
- also has very nice tooling for wasm

## Bootstraping a Rust Game of Life implementation
Quick recap:
Conway's Game of Life is a game/simulation of a universe of cells that live or die depending on their neighbors.
Each tick, if the cell was previously alive, it will stay alive if 2-3 of its neighbors were alive.
If it was dead, it needs exactly 3 of it's neighbors to be alive.
Otherwise the cell will be dead.

These simple rules can produce complex behaviour like this "glider gun" ([source](https://commons.wikimedia.org/wiki/File:Gospers_glider_gun.gif)):
![glider gun](https://upload.wikimedia.org/wikipedia/commons/e/e5/Gospers_glider_gun.gif)

### Implement simulation logic
To bootstap a crate for the game logic to reside in, I used one of the provided templates.
Using `npm init rust-webpack` ([source](https://github.com/rustwasm/rust-webpack-template)), I have a starting point without having to fiddle with npm, webpack or cargo.
Later I will go into more detail of what that template includes.

Need a struct to hold the universe.
I'm using a 2-dimensional array and store the current and last state, switching between them to avoid allocations.
The `#[wasm_bindgen]` annotation exposes the struct in the wasm module.
The build fails if an exposed function or type would expose an unexposed type as a field/in the signature.
```rust
const SIZE: usize = 16;
type Universe = [[u8; SIZE]; SIZE];

#[wasm_bindgen]
#[derive(Debug)]
pub struct GameOfLife {
    state: Universe,
    last: Universe,
}
```

Now I can implement a single tick of the universe by moving exchanging current and last state, rendering over the previous state.
Since the universe has a fixed size, I have to choose how to handle the borders:
Either treat cells outside the border as dead or wrap around to the other side, basically creating a torus.
I liked the idea of an endless glider, so I implemented the wrapping.
```rust
#[wasm_bindgen]
impl GameOfLife {
    pub fn tick(&mut self) {
        let tmp = self.last;
        self.last = self.state;
        self.state = tmp;

        for x in 0..self.last.len() {
            for y in 0..self.last[x].len() {
                self.state[x][y] = Self::will_be_alive(self.last, x, y)
            }
        }
    }

    fn will_be_alive(state: Universe, x: usize, y: usize) -> u8 {
        let mut alive_neighbors = 0;

				// Rust makes sure that usize can't get negative.
				// So using addition and modulo is simpler than a bunch of casting.
        for i in SIZE - 1..=SIZE + 1 {
            for j in SIZE - 1..=SIZE + 1 {
                if i == SIZE && j == SIZE { // don' count self
                    continue;
                }
                // turns into a wrapping universe
                let x_i = (x + i) % SIZE;
                let y_j = (y + j) % SIZE;
                alive_neighbors += state[x_i][y_j];
            }
        }

        return match (state[x][y], alive_neighbors) {
            (0, 3) | (1, 2) | (1, 3) => 1,
            _ => 0,
        };
    }
}
```

Add a method to translate the `Universe` into a `String` for easy pretty printing in JS.
```rust
#[wasm_bindgen]
impl GameOfLife {
    pub fn prettier_state(&self) -> String {
        let mut s = String::new();
        for line in &self.state {
            for cell in line {
                s += match cell {
                    1 => "█",
                    _ => "░",
                }
            }
            s += "\n"
        }
        s
    }
}
```

And generate the glider in the universe.
```rust
#[wasm_bindgen]
pub fn game() -> GameOfLife {
    let mut game = gameoflife::GameOfLife::new();
    game.set_alive(1, 2);
    game.set_alive(2, 3);
    game.set_alive(3, 1);
    game.set_alive(3, 2);
    game.set_alive(3, 3);
    game
}
```

Notice that all those functions are annotated with `#[wasm_bindgen]` so that they can be called from JS later on.
Lastly, the template provids a function with `#[wasm_bindgen(start)]` that is run once the module is imported.
In there, the game can be set up and the state is printed after each tick to `console.log()`
```rust
#[wasm_bindgen(start)]
pub fn main_js() -> Result<(), JsValue> {
    let mut game = game();
		for i in 0..100 {
		    game.tick();
				console::log_1(&JsValue::from_str(game.prettier_state));
		}

    Ok(())
}

```

### Looking into the template
- webpack -> wasm-pack-plugin -> runs wasm-pack -> runs wasm-bindgen
- interaction via C ABI: can do "C" external calls for js functions and lib type is cdyn
- `web_sys` for browser bindings like console (`println!` does not work)
- crate `console_error_panic_hook` for having panics print a trace to the console (could be added only for dev)
- `wasm-bindgen-test` to run tests in headless browsers (not used yet)
### What I understood of wasm-pack
- generated files

## Bring the game to life in the browser
The rust crate already simulates the game in the console.
But nobody looks into there, so let's improve on that.
### Handing Strings from Wasm to JS
- make it visible for normal ppl, set string as `textContent` of a `<pre>` element
- have to write some glue js, since i could not figure out proper async import (required because of [webpack limitations](https://github.com/webpack/webpack/issues/6615)).
- use `requestAnimationFrame()` to animate (some hardship to figure out how to wait between ticks to further slow down the animation)

### Can I get rid of manual JS completely?
- I tried and failed, could not find nice documentation (once I reached `setTimeout`)
- `Gloo` and its posts might allow me to so now
- (Perhaps do it for this post)

## It's really performant, right?
- well no, same code is far faster in js
- `mem::swap` sometimes works and then goes back to not working
- not multithreaded/parallel

## What's next
- Try again to get rid of js glue code (PURE Rust!!)
- Explore using `wasm-bindgen-test` for headless browser tests from Rust
- Performance optimizations? Wasm is supposed to be faster!

## Links
[wasm-life-introduction]: https://rustwasm.github.io/docs/book/introduction.html
[wasm-bindgen-docs]: https://rustwasm.github.io/docs/wasm-bindgen/
[wasm-pack-docs]: https://rustwasm.github.io/docs/wasm-pack/

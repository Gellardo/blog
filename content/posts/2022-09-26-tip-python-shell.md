---
title: "Tip: Spawn an interactive Python Shell anywhere in your code"
date: 2022-09-26T10:15:00+02:00
tags: ["short", "python"]
---

This is post is a collection of useful commands I always have to google for whenever I play around with new APIs/libraries.
Having an interactive shell to explore is incredibly helpful.
<!--more-->

So how do I spawn one anywhere in my code?

Well, either spawn a python shell (like when running `python`)
```import
import code
code.interact(local=locals())
```

Or just spawn `pdb` if you actually want to step through the following code.
```import
import pdb
pdb.set_trace()
```

Or just run your whole script and then get dropped into the usual python shell (including anything declared in the script), run it with:
```bash
python -i script.py
```

Or if you like to have a helpful python shell (requires ipython to be available):
```python
from IPython import embed
embed()
```
or if the current context already is running in an asyncio eventloop:
```
from IPython import embed
import nest_asyncio
nest_asyncio.apply()
embed(using="asyncio")
```

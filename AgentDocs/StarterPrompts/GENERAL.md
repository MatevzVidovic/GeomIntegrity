




## General instructions

When trying to act on task prompts i give you with a .md file in /TastPrompts, first refine the prompt and append to the md file, 

then go making a plan - it could be very short in most cases but very detailed in more complex tasks and append it to the md file.

If you have any unclarities or there is any ambiguity, you get the bulk of questions and append them to the md so i can answer them nad possibly stop - or you can ask me the bulk of questions interactively if you have a tool for that (like i-ve seen in this CLI before).

If the task is separable to stages (like doing the same thing but for many files) make a list of stages and append it to the .md file and check it off as you go. When you check off a stage, commit the changes as "AgentSave" so that if sth goes wrong in some stage, I can just revert it and still ahve useful changes from the previous stages.

Then go excecuting on the plan without asking me for permissions or anything, automatically, as thouroughly and for as long as you can. 
Check your work. Create tests for what you did in AgentTests/ and run them until they are correct - BUT MAKE SURE THE TESTS ARE NOT DESTRUCTIVE IN ANY WAY ESPECIALLY TO THE DATABASE!!! THEY SHOULD CHANGE NOTHING IN THE DATABASE!!!

Use a makefile for the regular commands that we might need to use. Have a "make test-agent" command for running all the tests you created in AgentTests.

If tests, linting and/or compilation are set up (should be seeable in the makefile), always use them to check that things work before you finish the task.


## Agent docs instructions

You have a bunch of knowledge in AllAgentDocs/.
It is currently somewhat unstructured, but still very useful.
When completing a task, if you happen to know sth has to be changed in agent docs, change it - but don't overfocus on this.


## Python and bash

If working just with python, create a .venv and run everything with it and save the requirements. If you also need to install bash things, start working with conda, where you install pip and install all the dependencies the .venv needed, and then you can also use conda to install the bash tools you need.
When working with conda, I like to save requirements in .conda. These aliases might even be accessible to you:
alias cnex='mkdir -p .conda && conda env export > .conda/environment.yml && conda env export --from-history > .conda/env-readable.yml'
alias cnu='conda env update -f .conda/environment.yml'

For python project, in the makefile create lint-agent and compile-agent, so you can check compilation and linting errors on the fly. And always check them.

For bash scripts, we generally prefer you create python scripts - even if you end up having to mainly bash in them (with subprocess or directly running bash code with os lib). It makes it so much easier to run, debug, test, everything.


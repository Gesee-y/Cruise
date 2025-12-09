# Cruise: DAG

Graph theory has been an ancient and well known subject. It's purpose is to study **graphs** which are structures that model pairwise relationships between objects. These object are called **vertices** and the links between them are **edges**.

Looking at this closely, we can see that games more or less fit into the graph model:

- We have multiple systems (audio, logics, physics, rendering, etc)
- Linked between them by dependencies (render needs physics, etc)

This way, we see that we can reasonably model our game with a graph but bot any graph, a **Directed Acyclic Graph** which is a subtype of graph with 2 guardrails:

- There are no cycles
- There is a direction to travel to node A to node B

Why this matters ?
Because it ensure there is no deadlocks or impossible execution path while trying to execute or systems in parallel.
Next it ensure that there is an order between systems execution.

More formally we will say that we modelled our game as a set of systems linked between them by unilateral dependencies, which forms a DAG.
This way using a topological sort, we are able to compute the optimal execution path for them and even leverage parallelism for optimal execution.

That's a brief overview of how Cruise handles your games.

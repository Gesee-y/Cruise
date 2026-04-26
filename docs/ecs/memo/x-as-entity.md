# X as entities

The term **X as entities** is about a design philosophy where everything in an ECS is an entity.
While this seems appealing as it makes the ECS way simpler, Cruise ECS doesn't integrate any of them.
We will enumerate why

## [Systems as Entities](https://github.com/bevyengine/bevy/issues/16618)

This is about making game systems entities, allowing you to add them tags (like `IsPaused`, `OneShot`, etc,) or data.
This makes game systems queryable with multiple criterion, and can allow better scheduling.
Cruise ECS doesn't have it for the simple reason that it doesn't have a dedicated scheduler.
Everyone is free to make a scheduler as a plugin, integrate systems as entities if he want. That's only fair.

## [Components as Entities](https://ajmmertens.medium.com/doing-a-lot-with-a-little-ecs-identifiers-25a72bd2647)

This one is about letting components be entities. This enable 2 things:

- **Entities as components**: You can for example attach the `entity_x` to the `entity_y`. This is the basic of [entities relationships](https://ajmmertens.medium.com/building-games-in-ecs-with-entity-relationships-657275ba2c6c). This has the inconvenience of raising the number of components and fragmenting the memory (for archetype ECS).

- **Scriptable components**: Meaning components can be added at runtime with fields being editable (a `Position` entity on which you add the `x` , `y` components). Then being able to query them without any hassle.

Cruise doesn't integrate those as entities relationships can easily be handled by **Query filters**, which is how the Scene tree plugin is built. They offer the basic blocks to model relationships without the downside of components as entities.
About scriptable components, Cruise is using many [statics assumptions]() making those almost not possible at the core level but not at the user level. It's still possible to have an entity named `Position` with the necessary fields and track through `QueryFilter`s entities possessing that component and enabling queries without affecting the main storage, that's an idea for a plugin, not a refactor for the core.

## [Assets as entities](https://github.com/bevyengine/bevy/issues/11266)

Assets as entities refers to having assets just be entities with the corresponding assets data.
This allows for simpler changes tracking, better handling for assets, accelerate lookups and more.

This doesn't need to be integrated in Cruise ECS as this is fully user side logics.



## [0.3.0] - 2024-08-28

 - Added Plumbing::Valve
 - Reimplemented Plumbing::Pipe to use Plumbing::Valve

## [0.2.2] - 2024-08-25

 - Added Plumbing::RubberDuck

## [0.2.1] - 2024-08-25

 - Split the Pipe implementation between the Pipe and EventDispatcher
 - Use different EventDispatchers to handle fibers or inline pipes
 - Renamed Chain to Pipeline

## [0.2.0] - 2024-08-14

 - Added optional Dry::Validation support
 - Use Async for fiber-based pipes

## [0.1.2] - 2024-08-14

 - Removed dependencies
 - Removed Ractor-based concurrent pipe (as I don't trust it yet)

## [0.1.1] - 2024-08-14

- Tidied up the code
- Added Plumbing::Chain

## [0.1.0] - 2024-04-13

- Initial release

## [Unreleased]


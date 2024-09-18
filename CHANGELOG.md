## [0.4.5] - 2024-09-18

 - `become` matchers available to other gems
 - `wait_for`

## [0.4.4] - 2024-09-18

 - Various bugfixes around the threading implementation

## [0.4.1] - 2024-09-16

 - Added `safely` to allow actors to run code within their own context

## [0.4.0] - 2024-09-15

 - Added #as_actor to allow actors to pass references to themselves

## [0.3.3] - 2024-09-14

 - Added :threaded and :rails modes
 - RubberDuck now works with Module and Class

## [0.3.2] - 2024-09-13

 - URG - somehow I'd managed to exclude the lib folder from the gem contents

## [0.3.1] - 2024-09-03

 - Added `ignore_result` for queries on Plumbing::Valves

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


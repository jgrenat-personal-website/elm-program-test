module TestContext.EffectSimulation exposing
    ( EffectSimulation
    , SimulationState
    , clearOutgoingPortValues
    , emptySimulationState
    , init
    , outgoingPortValues
    , queueTask
    , stepWorkQueue
    )

import Dict exposing (Dict)
import Fifo exposing (Fifo)
import Json.Encode
import PairingHeap exposing (PairingHeap)
import SimulatedEffect exposing (SimulatedEffect, SimulatedTask)


type alias EffectSimulation msg effect =
    { deconstructEffect : effect -> SimulatedEffect msg
    , workQueue : Fifo (SimulatedTask msg msg)
    , state : SimulationState msg
    , outgoingPortValues : Dict String (List Json.Encode.Value)
    }


init : (effect -> SimulatedEffect msg) -> EffectSimulation msg effect
init f =
    { deconstructEffect = f
    , workQueue = Fifo.empty
    , state = emptySimulationState
    , outgoingPortValues = Dict.empty
    }


type alias SimulationState msg =
    { http : Dict ( String, String ) (SimulatedEffect.HttpRequest msg msg)
    , futureTasks : PairingHeap Int (() -> SimulatedTask msg msg)
    , nowMs : Int
    }


emptySimulationState : SimulationState msg
emptySimulationState =
    { http = Dict.empty
    , futureTasks = PairingHeap.empty
    , nowMs = 0
    }


queueTask : SimulatedTask msg msg -> EffectSimulation msg effect -> EffectSimulation msg effect
queueTask task simulation =
    { simulation
        | workQueue = Fifo.insert task simulation.workQueue
    }


stepWorkQueue : EffectSimulation msg effect -> Maybe ( EffectSimulation msg effect, Maybe msg )
stepWorkQueue simulation =
    case Fifo.remove simulation.workQueue of
        ( Nothing, _ ) ->
            Nothing

        ( Just task, rest ) ->
            let
                ( newState, msg ) =
                    simulateTask task simulation.state
            in
            Just
                ( { simulation
                    | workQueue = rest
                    , state = newState
                  }
                , msg
                )


simulateTask : SimulatedTask msg msg -> SimulationState msg -> ( SimulationState msg, Maybe msg )
simulateTask task simulationState =
    case task of
        SimulatedEffect.Succeed msg ->
            ( simulationState, Just msg )

        SimulatedEffect.Fail msg ->
            ( simulationState, Just msg )

        SimulatedEffect.HttpTask request ->
            ( { simulationState
                | http =
                    Dict.insert ( request.method, request.url )
                        request
                        simulationState.http
              }
            , Nothing
            )

        SimulatedEffect.SleepTask delay onResult ->
            ( { simulationState
                | futureTasks =
                    PairingHeap.insert (simulationState.nowMs + round delay) onResult simulationState.futureTasks
              }
            , Nothing
            )


outgoingPortValues : String -> EffectSimulation msg effect -> List Json.Encode.Value
outgoingPortValues portName simulation =
    Dict.get portName simulation.outgoingPortValues
        |> Maybe.withDefault []
        |> List.reverse


clearOutgoingPortValues : String -> EffectSimulation msg effect -> EffectSimulation msg effect
clearOutgoingPortValues portName simulation =
    { simulation | outgoingPortValues = Dict.remove portName simulation.outgoingPortValues }
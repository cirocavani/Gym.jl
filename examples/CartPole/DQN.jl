using Flux, Gym
using Flux.Optimise: Optimiser
using Statistics: mean
using DataStructures: CircularBuffer
using Distributions: sample
using Printf

# Load game environment
env = make("CartPole-v0", :human_pane)
reset!(env)

# ----------------------------- Parameters -------------------------------------

STATE_SIZE = length(env._env.state)    # 4
ACTION_SIZE = length(env._env.action_space) # 2
MEM_SIZE = 100_000
BATCH_SIZE = 64
γ = 1f0   			  # discount rate

# Exploration params
ϵ = 1f0       # Initial exploration rate
ϵ_MIN = 1f-2    # Final exploratin rate
ϵ_DECAY = 995f-3

# Optimiser params
η = 1f-2   # Learning rate
η_decay = 1f-2

memory = CircularBuffer{Any}(MEM_SIZE) # Used to remember past results

# ------------------------------ Model Architecture ----------------------------

model = Chain(Dense(STATE_SIZE, 24, tanh),
              Dense(24, 48, tanh),
              Dense(48, ACTION_SIZE)) |> gpu

loss(x, y) = Flux.mse(model(x |> gpu), y)

opt = Optimiser(ADAM(η), InvDecay(η_decay))

# ----------------------------- Helper Functions -------------------------------

get_ϵ(e) = max(ϵ_MIN, min(ϵ, 1f0 - log10(e * ϵ_DECAY)))

remember(state, action, reward, next_state, done) =
  push!(memory, (cpu(state), action, reward, cpu(next_state), done))

function action(state, train=true)
  train && rand() <= get_ϵ(e) && (return Gym.sample(env._env.action_space))
  act_values = model(state |> gpu)
  return Flux.onecold(act_values)
end

function replay()
  global ϵ
  batch_size = min(BATCH_SIZE, length(memory))
  minibatch = sample(memory, batch_size, replace = false)

  x = []
  y = []
  for (iter, (state, action, reward, next_state, done)) in enumerate(minibatch)
    target = reward
    if !done
      target += γ * maximum(cpu(model(next_state |> gpu)))
    end

    target_f = cpu(model(state |> gpu))
    target_f[action] = target

    push!(x, state)
    push!(y, target_f)
  end
  x = hcat(x...) |> gpu
  y = hcat(y...) |> gpu
  Flux.train!(loss, params(model), [(x, y)], opt)

  ϵ *= ϵ > ϵ_MIN ? ϵ_DECAY : 1.0f0
end

function episode!(env, train=true, draw=false)
  done = false
  total_reward = 0f0
  while !done
    draw && render!(env)
    s = env._env.state
    a = action(s, train)
    s′, r, done, _ = step!(env, a)
    total_reward += r
    train && remember(s, a, r, s′, done)
    draw && sleep(0.01)
  end

  total_reward
end

# ------------------------------ Training --------------------------------------

e = 1
scores = CircularBuffer{Float32}(100)

while true
  global e
  reset!(env)
  total_reward = episode!(env)
  push!(scores, total_reward)
  print("Episode: $e | Score: $total_reward ")
  last_100_mean = mean(scores)
  print("Last 100 episodes mean score: $(@sprintf "%6.2f" last_100_mean)")
  if last_100_mean > 195
    println("\nCartPole-v0 solved!")
    break
  end
  println()
  replay()
  e += 1
end

# -------------------------------- Testing -------------------------------------

ee = 1

while true
  global ee
  reset!(env)
  total_reward = episode!(env, false, true)
  println("Episode: $ee | Score: $total_reward")
  ee += 1
end

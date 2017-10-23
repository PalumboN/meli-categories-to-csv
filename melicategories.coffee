_ = require('lodash')
fs = require('fs')
rp = require('request-promise')
request = require('request')
Promise = require('bluebird')
promiseRetry = require('promise-retry')

tr = require('tor-request')
tr.TorControlPort.password = 'giraffe'


Promise.promisifyAll fs
Promise.promisifyAll request
Promise.promisifyAll tr
Promise.promisifyAll tr.request

createWriteStream = (path) -> 
  writer = fs.createWriteStream path
  Promise.promisifyAll writer
  writer

resultWriter = createWriteStream "results.txt"

header = "Id, Categoría 1, Categoría 2, Categoría 3, Categoría 4, Categoría 5, Categoría 6, Categoría 7, Categoría 8 \n"

baseMeliApi = "https://api.mercadolibre.com"

mlaCategories = baseMeliApi + "/sites/MLA/categories"

categoryUri = (id) -> baseMeliApi + "/categories/#{id}"


lastChange = new Date()
shouldChangeIp = ->
  (new Date() - lastChange) > 20 * 1000 #ms

changeIp = ->
  if shouldChangeIp()
    lastChange = new Date()
    tr.newTorSession (err) -> if (err?) then console.log err else console.log "Cambio de IP"
  else
    console.log "Ya se cambió la IP"

get = (uri) -> 
  Promise.resolve(
    promiseRetry (retry, number) -> 
      if (number > 1)
        console.log "Reintentando ##{number} GET #{uri}" 
        changeIp()
      tr.request.getAsync { uri, json: true }
      .then ({body}) -> body
      .catch retry
  )

getChildren = (category) -> 
  get categoryUri(category.id)
  .then _.property("children_categories")

getFullyPath = (category) ->
  console.log "Armando path: #{category.name}"
  getChildren category
  .map (child) -> "#{category.name}, #{child.name}"

searchLeafCategories = (category, writer) ->
  getChildren category
  .then (children) ->
    isLeaf = children.length == 0
    if (isLeaf)
      console.log "#{category.name} es hoja!"
      savePathFromRoot category, writer
    else
      Promise.all children.map (it) -> searchLeafCategories it, writer
  .tapCatch (err) -> 
    console.log err
    resultWriter.writeAsync "¡ERROR AL CARGAR #{category.name} - #{category.id}!" + "\n"

saveLeafIdonly = (category) ->
  writer.writeAsync category.id + "\n"

savePathFromRoot = (category, writer) ->
  console.log "Buscando path_from_root de #{category.name}"
  get categoryUri(category.id)
  .then _.property("path_from_root")
  .then (pathCategories) -> _.reduce pathCategories, concatNameCategory, ""
  .then (path) -> "#{category.id}, " + path
  .tap (path) -> console.log "Guardando: " + path
  .tap (path) -> writer.writeAsync path + "\n"

concatNameCategory = (acum, category) -> acum + "#{category.name}, "




writer = createWriteStream "categorias.csv"
writer.writeAsync header
.then -> get mlaCategories
.then (it) -> _(it).reverse().value()
.each (category) ->
  console.log "Analizando raíz: #{category.name}"
  searchLeafCategories category, writer
  .then -> resultWriter.writeAsync "¡Todas las hojas de #{category.name} encontradas!" + "\n"
  .catch (err) -> resultWriter.writeAsync "ERROR AL BUSCAR EN #{category.name}: " + JSON.stringify(err) + "\n"

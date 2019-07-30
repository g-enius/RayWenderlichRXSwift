/*
 * Copyright (c) 2016 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import Foundation
import RxSwift
import RxDataSources
import Action

typealias TaskSection = AnimatableSectionModel<String, TaskItem>

struct TasksViewModel {
  let sceneCoordinator: SceneCoordinatorType
  let taskService: TaskServiceType

  lazy var statistics: Observable<TaskStatistics> = self.taskService.statistics()

  init(taskService: TaskServiceType, coordinator: SceneCoordinatorType) {
    self.taskService = taskService
    self.sceneCoordinator = coordinator
  }

    func onToggle(task: TaskItem) -> CocoaAction {
        return CocoaAction {
            return self.taskService.toggle(task: task)
                .map{_ in }
        }
    }
    
    func onDelete(task: TaskItem) -> CocoaAction {
        return CocoaAction {
            return self.taskService.delete(task: task)
        }
    }
    
    func onUpdateTitle(task: TaskItem) -> Action<String, Void> {
        return Action { newTitle in
            return self.taskService
                .update(task: task,
                        title: newTitle)
                .map{_ in }
        }
    }
    
    //read-only computed variable
    var sectionedItems: Observable<[TaskSection]> {
        return self.taskService.tasks()
            .map{ results -> [TaskSection] in
                let dueTasks = results
                .filter("checked == nil")
                .sorted(byKeyPath: "added", ascending: false)
                
                let doneTask = results
                .filter("checked != nil")
                .sorted(byKeyPath: "checked", ascending: false)
                
                return [
                    TaskSection(model: "Due Tasks", items: dueTasks.toArray()),
                    TaskSection(model: "Done Tasks", items: doneTask.toArray())
                ]
            }
    }
    
    func onCreateTask() -> CocoaAction {
        return CocoaAction {
            return self.taskService
            .createTask(title: "")
                .flatMap{ task -> Observable<Void> in
//1) First View Model instantiates the Second view Model
                    let editTaskViewModel = EditTaskViewModel(task: task,
                                                              coordinator: self.sceneCoordinator,
                                                              updateAction: self.onUpdateTitle(task: task),
                                                              cancelAction: self.onDelete(task: task))
//2) calls for transition
//push/present is decided by parent view model, but pop/dismiss is decided inside its own view model
// <inside Scene Cordinator>
//3) Scene Coordinator instantiates the Second View Controller
//4) Scene Coordinator binds second VC and VM together
//5) Scene Coordinator presents second VC
                    return self.sceneCoordinator
                    .transition(to: Scene.editTask(editTaskViewModel), type: .push)
                    .asObservable()
                        .map{ _ in }
                }
        }
    }
    
    //lazy read & write computed variable
    lazy var editAdction: Action<TaskItem, Never> = { this in
        return Action { task -> Observable<Never> in
            let editViewModel = EditTaskViewModel(task: task,
                                                  coordinator: this.sceneCoordinator,
                                                  updateAction: this.onUpdateTitle(task:task))
            return this.sceneCoordinator
                .transition(to: Scene.editTask(editViewModel), type: .push)
                .asObservable()
        }
    }(self)
    
    lazy var deleteAction: Action<TaskItem, Void> = { (service: TaskServiceType) in
        return Action { task in
            return service.delete(task: task)
        }
    }(self.taskService)
}

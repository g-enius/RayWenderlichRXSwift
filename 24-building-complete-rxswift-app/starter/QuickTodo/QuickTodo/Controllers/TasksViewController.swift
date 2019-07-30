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

import UIKit
import RxSwift
import RxDataSources
import Action

class TasksViewController: UIViewController, BindableType {
  
  @IBOutlet var tableView: UITableView!
  @IBOutlet var statisticsLabel: UILabel!
  @IBOutlet var newTaskButton: UIBarButtonItem!
//    That ! in the protocol is due to “TaskViewControler” and “EditTaskViewController” also define the viewModel as a var !. That’s a “have-to-do” as there are no inits there.
  var viewModel: TasksViewModel!
  var dataSource: RxTableViewSectionedAnimatedDataSource<TaskSection>!

  var disposeBag = DisposeBag()
    
  override func viewDidLoad() {
    super.viewDidLoad()
    
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 60

    configureDataSource()

    setEditing(true, animated: false)
  }
  
  func bindViewModel() {
    viewModel.sectionedItems
    .bind(to: tableView.rx.items(dataSource: dataSource))
    .disposed(by: disposeBag)

    newTaskButton.rx.action = viewModel.onCreateTask()
    
    tableView.rx.itemSelected
        .do(onNext: { [unowned self] indexPath in
            self.tableView.deselectRow(at: indexPath, animated: false)
        })
        .map { [unowned self] indexPath in
            try! self.dataSource.model(at:indexPath) as! TaskItem
        }
        .subscribe(viewModel.editAdction.inputs)//??????????????/
        .disposed(by: disposeBag)
    
    tableView.rx.itemDeleted
        .map { [unowned self] indexPath in
            try! self.tableView.rx.model(at:indexPath)
        }
        .debug("deleteActionInput:")
        .subscribe(viewModel.deleteAction.inputs)
        .disposed(by: disposeBag)
    
    viewModel.statistics
        .subscribe(onNext: { [unowned self] stats in
            let total = stats.todo + stats.done
            self.statisticsLabel.text = "\(total) tasks, \(stats.todo) due."
        })
        .disposed(by: disposeBag)
    
  }

  fileprivate func configureDataSource() {
    dataSource = RxTableViewSectionedAnimatedDataSource<TaskSection>(configureCell: { [weak self] (dataSource, tableView, indexPath, item) -> UITableViewCell in
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskItemCell", for: indexPath) as! TaskItemTableViewCell
        if let strongSelf = self {
            cell.configure(with: item, action: strongSelf.viewModel.onToggle(task: item))
        }
        return cell
        
        }, titleForHeaderInSection: { (dataSource, index) -> String? in
            dataSource.sectionModels[index].model
        },
           canEditRowAtIndexPath: { _, _ in true}
        )
    }

}

class TextInputField extends React.Component {
    render() {
        return (
            <div className="form-group row">
                <label htmlFor="name-input" className="col-md-2 col-form-label">{this.props.title}</label>
                <div className="col-md-10">
                    <input className="form-control"
                           type="text"
                           value={this.props.value}
                           id={this.props.name}
                           readOnly={this.props.readOnly}
                           onChange={(e) => this.props.updateInput(this.props.name, e.target.value)}/>
                </div>
            </div>
        );
    }
}